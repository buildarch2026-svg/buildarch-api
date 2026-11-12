<?php

namespace Tests\Feature;

use App\Models\OtpChallenge;
use App\Models\User;
use App\Services\GoogleIdentityVerificationUnavailable;
use App\Services\GoogleIdTokenVerifier;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Mockery\MockInterface;
use Tests\TestCase;

class OtpApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    protected function setUp(): void
    {
        parent::setUp();
        $this->app['env'] = 'local';
        config([
            'services.google.client_id' => 'test-google-web-client-id',
            'services.whatsapp.access_token' => null,
            'services.whatsapp.phone_number_id' => null,
            'services.whatsapp.otp_template' => null,
            'services.whatsapp.otp_template_language' => 'en_US',
            'services.whatsapp.graph_api_version' => 'v26.0',
        ]);
    }

    public function test_request_creates_a_challenge_for_an_e164_number(): void
    {
        $response = $this->postJson('/api/auth/otp/request', [
            'phone_number' => '+919876543210',
        ]);

        $response->assertOk()->assertJsonPath('expires_in', 300);
        $this->assertDatabaseHas('otp_challenges', [
            'phone_number' => '+919876543210',
            'attempts' => 0,
        ]);
    }

    public function test_profile_phone_request_is_rate_limited(): void
    {
        for ($attempt = 0; $attempt < 3; $attempt++) {
            $this->postJson('/api/user/profile/phone/request', [
                'phone_number' => '+91987654321'.($attempt + 1),
            ])->assertOk();
        }
        $this->postJson('/api/user/profile/phone/request', [
            'phone_number' => '+919876543214',
        ])->assertTooManyRequests();
    }

    public function test_profile_phone_otp_request_is_public_but_verification_requires_authentication(): void
    {
        $this->postJson('/api/user/profile/phone/request', [
            'phone_number' => '+919876543212',
        ])->assertOk()
            ->assertJsonPath('expires_in', 300);

        $this->assertDatabaseHas('otp_challenges', [
            'phone_number' => '+919876543212',
            'attempts' => 0,
        ]);

        $this->postJson('/api/user/profile/phone/verify', [
            'phone_number' => '+919876543212',
            'code' => '123456',
        ])->assertUnauthorized();
    }

    public function test_request_sends_the_otp_using_the_configured_whatsapp_template(): void
    {
        config([
            'services.whatsapp.access_token' => 'test-access-token',
            'services.whatsapp.phone_number_id' => '123456789',
            'services.whatsapp.otp_template' => 'build_arch_otp',
        ]);
        $sentCode = null;
        Http::fake(function (HttpRequest $request) use (&$sentCode) {
            $sentCode = $request['template']['components'][0]['parameters'][0]['text'];

            return Http::response(['messages' => [['id' => 'test-message-id']]], 200);
        });

        $response = $this->postJson('/api/auth/otp/request', [
            'phone_number' => '+919876543210',
        ]);

        $response->assertOk()
            ->assertJsonPath('message', 'Verification code sent via WhatsApp.')
            ->assertJsonPath('expires_in', 300)
            ->assertJsonMissingPath('code');
        $this->assertIsString($sentCode);
        $this->assertMatchesRegularExpression('/^\d{6}$/', $sentCode);
        $this->assertTrue(Hash::check(
            $sentCode,
            OtpChallenge::where('phone_number', '+919876543210')->value('code_hash'),
        ));
        Http::assertSent(function (HttpRequest $request) use ($sentCode): bool {
            return $request->url()
                    === 'https://graph.facebook.com/v26.0/123456789/messages'
                && $request->hasHeader('Authorization', 'Bearer test-access-token')
                && $request['messaging_product'] === 'whatsapp'
                && $request['to'] === '919876543210'
                && $request['type'] === 'template'
                && $request['template']['name'] === 'build_arch_otp'
                && $request['template']['language']['code'] === 'en_US'
                && $request['template']['components'][0]['parameters'][0]['text'] === $sentCode;
        });
    }

    public function test_failed_whatsapp_delivery_does_not_leave_an_active_challenge(): void
    {
        config([
            'services.whatsapp.access_token' => 'test-access-token',
            'services.whatsapp.phone_number_id' => '123456789',
            'services.whatsapp.otp_template' => 'build_arch_otp',
        ]);
        Http::fake([
            'https://graph.facebook.com/*' => Http::response(['error' => ['message' => 'rejected']], 400),
        ]);

        $this->postJson('/api/auth/otp/request', [
            'phone_number' => '+919876543210',
        ])->assertServiceUnavailable()
            ->assertJsonPath(
                'message',
                'Could not send a verification code. Please try again.',
            );

        $this->assertDatabaseMissing('otp_challenges', [
            'phone_number' => '+919876543210',
        ]);
    }

    public function test_profile_phone_request_rejects_a_number_owned_by_another_user(): void
    {
        $user = User::factory()->create(['phone_number' => null]);
        User::factory()->create(['phone_number' => '+919876543210']);
        $token = $user->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->postJson('/api/user/profile/phone/request', [
                'phone_number' => '+919876543210',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('phone_number');

        $this->assertDatabaseMissing('otp_challenges', [
            'phone_number' => '+919876543210',
        ]);
    }

    public function test_verify_accepts_the_code_and_consumes_the_challenge(): void
    {
        OtpChallenge::create([
            'phone_number' => '+919876543210',
            'code_hash' => Hash::make('123456'),
            'attempts' => 0,
            'expires_at' => now()->addMinutes(5),
        ]);

        $response = $this->postJson('/api/auth/otp/verify', [
            'phone_number' => '+919876543210',
            'code' => '123456',
        ]);

        $response->assertOk()->assertJsonPath('verified', true);
        $this->assertDatabaseMissing('otp_challenges', [
            'phone_number' => '+919876543210',
        ]);
    }

    public function test_consumed_otp_cannot_be_reused_to_create_another_session(): void
    {
        OtpChallenge::create([
            'phone_number' => '+919876543210',
            'code_hash' => Hash::make('123456'),
            'attempts' => 0,
            'expires_at' => now()->addMinutes(5),
        ]);

        $this->postJson('/api/auth/otp/verify', [
            'phone_number' => '+919876543210',
            'code' => '123456',
        ])->assertOk()
            ->assertJsonPath('verified', true);

        $this->postJson('/api/auth/otp/verify', [
            'phone_number' => '+919876543210',
            'code' => '123456',
        ])->assertUnprocessable()
            ->assertJsonPath('message', 'Code is invalid or expired.');

        $this->assertDatabaseCount('personal_access_tokens', 1);
        $this->assertDatabaseMissing('otp_challenges', [
            'phone_number' => '+919876543210',
        ]);
    }

    public function test_expired_otp_is_rejected(): void
    {
        OtpChallenge::create([
            'phone_number' => '+919876543210',
            'code_hash' => Hash::make('123456'),
            'attempts' => 0,
            'expires_at' => now()->subSecond(),
        ]);

        $this->postJson('/api/auth/otp/verify', [
            'phone_number' => '+919876543210',
            'code' => '123456',
        ])->assertUnprocessable()
            ->assertJsonPath('message', 'Code is invalid or expired.');

        $this->assertDatabaseHas('otp_challenges', [
            'phone_number' => '+919876543210',
        ]);
        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    public function test_otp_challenge_is_removed_after_too_many_incorrect_attempts(): void
    {
        OtpChallenge::create([
            'phone_number' => '+919876543210',
            'code_hash' => Hash::make('123456'),
            'attempts' => 0,
            'expires_at' => now()->addMinutes(5),
        ]);

        for ($attempt = 0; $attempt < 5; $attempt++) {
            $this->postJson('/api/auth/otp/verify', [
                'phone_number' => '+919876543210',
                'code' => '654321',
            ])->assertUnprocessable()
                ->assertJsonPath('message', 'Code is incorrect.');
        }

        $this->postJson('/api/auth/otp/verify', [
            'phone_number' => '+919876543210',
            'code' => '654321',
        ])->assertTooManyRequests()
            ->assertJsonPath('message', 'Too many attempts. Request a new code.');

        $this->assertDatabaseMissing('otp_challenges', [
            'phone_number' => '+919876543210',
        ]);
    }

    public function test_verify_creates_a_user_and_returns_a_session_token(): void
    {
        OtpChallenge::create([
            'phone_number' => '+919876543210',
            'code_hash' => Hash::make('654321'),
            'attempts' => 0,
            'expires_at' => now()->addMinutes(5),
        ]);

        $response = $this->postJson('/api/auth/otp/verify', [
            'phone_number' => '+919876543210',
            'code' => '654321',
        ]);

        $response->assertOk()
            ->assertJsonPath('verified', true)
            ->assertJsonPath('user.phone_number', '+919876543210')
            ->assertJsonPath('user.profile_complete', false)
            ->assertJsonStructure(['token', 'user']);

        $this->assertDatabaseHas('users', [
            'phone_number' => '+919876543210',
        ]);
        $this->assertNotEmpty($response->json('token'));
    }

    public function test_verify_marks_existing_complete_profile(): void
    {
        $user = User::factory()->create([
            'phone_number' => '+919876543210',
            'location' => 'Chennai, Tamil Nadu',
            'role' => 'homeOwner',
        ]);
        OtpChallenge::create([
            'phone_number' => '+919876543210',
            'code_hash' => Hash::make('123456'),
            'attempts' => 0,
            'expires_at' => now()->addMinutes(5),
        ]);

        $response = $this->postJson('/api/auth/otp/verify', [
            'phone_number' => '+919876543210',
            'code' => '123456',
        ]);

        $response->assertOk()
            ->assertJsonPath('user.id', $user->id)
            ->assertJsonPath('user.location', 'Chennai, Tamil Nadu')
            ->assertJsonPath('user.role', 'homeOwner')
            ->assertJsonPath('user.profile_complete', true);
        $this->assertDatabaseCount('users', 1);
    }

    public function test_verifying_two_phone_numbers_creates_separate_accounts(): void
    {
        foreach ([
            '+919876543210' => '123456',
            '+919876543211' => '654321',
        ] as $phoneNumber => $code) {
            OtpChallenge::create([
                'phone_number' => $phoneNumber,
                'code_hash' => Hash::make($code),
                'attempts' => 0,
                'expires_at' => now()->addMinutes(5),
            ]);
        }

        $firstAccount = $this->postJson('/api/auth/otp/verify', [
            'phone_number' => '+919876543210',
            'code' => '123456',
        ])->assertOk()->json('user.id');

        $secondAccount = $this->postJson('/api/auth/otp/verify', [
            'phone_number' => '+919876543211',
            'code' => '654321',
        ])->assertOk()->json('user.id');

        $this->assertNotSame($firstAccount, $secondAccount);
        $this->assertDatabaseCount('users', 2);
    }

    public function test_logout_revokes_only_the_current_api_token(): void
    {
        $user = User::factory()->create();
        $firstToken = $user->createToken('first-device');
        $secondToken = $user->createToken('second-device');

        $this->withToken($firstToken->plainTextToken)
            ->postJson('/api/auth/logout')
            ->assertOk();

        $this->app['auth']->forgetGuards();
        $this->withToken($firstToken->plainTextToken)
            ->getJson('/api/user')
            ->assertUnauthorized();

        $this->app['auth']->forgetGuards();
        $this->withToken($secondToken->plainTextToken)
            ->getJson('/api/user')
            ->assertOk();

        $this->assertDatabaseHas('personal_access_tokens', [
            'id' => $secondToken->accessToken->id,
            'tokenable_id' => $user->id,
        ]);
        $this->assertDatabaseMissing('personal_access_tokens', [
            'id' => $firstToken->accessToken->id,
        ]);
    }

    public function test_google_login_creates_user_and_returns_session_token(): void
    {
        $this->mockVerifiedGoogleToken([
            'sub' => 'google-123',
            'email' => 'alex.google@example.com',
            'email_verified' => true,
            'name' => 'Alex Google',
        ]);

        $response = $this->postJson('/api/auth/google', [
            'id_token' => 'verified-test-token',
            'email' => 'attacker@example.com',
            'name' => 'Untrusted Name',
            'google_id' => 'untrusted-google-id',
        ]);

        $response->assertOk()
            ->assertJsonPath('verified', true)
            ->assertJsonPath('user.email', 'alex.google@example.com')
            ->assertJsonPath('user.name', 'Alex Google')
            ->assertJsonPath('user.google_id', 'google-123')
            ->assertJsonStructure(['token', 'user']);

        $this->assertDatabaseHas('users', [
            'email' => 'alex.google@example.com',
            'google_id' => 'google-123',
        ]);
        $this->assertNotEmpty($response->json('token'));
    }

    public function test_google_login_marks_existing_complete_profile(): void
    {
        $this->mockVerifiedGoogleToken([
            'sub' => 'google-123',
            'email' => 'alex.google@example.com',
            'email_verified' => true,
            'name' => 'Alex Google',
        ]);

        $user = User::factory()->create([
            'email' => 'alex.google@example.com',
            'google_id' => 'google-123',
            'phone_number' => '+919876543210',
            'location' => 'Chennai, Tamil Nadu',
            'role' => 'homeOwner',
        ]);

        $response = $this->postJson('/api/auth/google', [
            'id_token' => 'verified-test-token',
        ]);

        $response->assertOk()
            ->assertJsonPath('user.id', $user->id)
            ->assertJsonPath('user.location', 'Chennai, Tamil Nadu')
            ->assertJsonPath('user.role', 'homeOwner')
            ->assertJsonPath('user.profile_complete', true);
        $this->assertDatabaseCount('users', 1);
    }

    public function test_google_login_requires_an_id_token(): void
    {
        $this->postJson('/api/auth/google', [
            'email' => 'alex.google@example.com',
            'name' => 'Alex Google',
            'google_id' => 'google-123',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('id_token');

        $this->assertDatabaseCount('users', 0);
    }

    public function test_google_login_rejects_an_invalid_id_token(): void
    {
        $this->mockVerifiedGoogleToken(null);

        $this->postJson('/api/auth/google', [
            'id_token' => 'verified-test-token',
        ])->assertUnauthorized();

        $this->assertDatabaseCount('users', 0);
    }

    public function test_google_login_returns_service_unavailable_when_verification_is_down(): void
    {
        $this->mock(GoogleIdTokenVerifier::class, function (MockInterface $mock): void {
            $mock->shouldReceive('verify')
                ->once()
                ->with('verified-test-token')
                ->andThrow(new GoogleIdentityVerificationUnavailable);
        });

        $this->postJson('/api/auth/google', [
            'id_token' => 'verified-test-token',
        ])->assertServiceUnavailable();

        $this->assertDatabaseCount('users', 0);
    }

    public function test_authenticated_user_can_save_basic_profile(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('test')->plainTextToken;

        $response = $this->withToken($token)->patchJson('/api/user/profile', [
            'name' => 'Alex Builder',
            'location' => 'Chennai, Tamil Nadu',
            'role' => 'homeOwner',
        ]);

        $response->assertOk()
            ->assertJsonPath('user.name', 'Alex Builder')
            ->assertJsonPath('user.location', 'Chennai, Tamil Nadu')
            ->assertJsonPath('user.role', 'homeOwner');

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'name' => 'Alex Builder',
            'location' => 'Chennai, Tamil Nadu',
            'role' => 'homeOwner',
        ]);
    }

    public function test_authenticated_user_can_save_designer_role(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('test')->plainTextToken;

        $this->withToken($token)->patchJson('/api/user/profile', [
            'name' => 'Alex Designer',
            'location' => 'Chennai, Tamil Nadu',
            'role' => 'designer',
        ])->assertOk()->assertJsonPath('user.role', 'designer');
    }

    public function test_profile_rejects_removed_role_categories(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('test')->plainTextToken;

        foreach (['architect', 'engineer', 'interiorDesigner'] as $role) {
            $this->withToken($token)->patchJson('/api/user/profile', [
                'name' => 'Alex User',
                'location' => 'Chennai, Tamil Nadu',
                'role' => $role,
            ])->assertUnprocessable();
        }
    }

    public function test_authenticated_google_user_can_attach_a_verified_phone_number(): void
    {
        $user = User::factory()->create([
            'email' => 'alex.google@example.com',
            'google_id' => 'google-123',
            'phone_number' => null,
        ]);
        $token = $user->createToken('test')->plainTextToken;
        OtpChallenge::create([
            'phone_number' => '+919876543210',
            'code_hash' => Hash::make('123456'),
            'attempts' => 0,
            'expires_at' => now()->addMinutes(5),
        ]);

        $this->withToken($token)
            ->postJson('/api/user/profile/phone/verify', [
                'phone_number' => '+919876543210',
                'code' => '123456',
            ])
            ->assertOk()
            ->assertJsonPath('verified', true)
            ->assertJsonPath('phone_number', '+919876543210');

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'phone_number' => '+919876543210',
        ]);
        $this->assertDatabaseMissing('otp_challenges', [
            'phone_number' => '+919876543210',
        ]);
    }

    public function test_authenticated_user_cannot_attach_a_phone_owned_by_another_user(): void
    {
        $user = User::factory()->create(['phone_number' => null]);
        User::factory()->create(['phone_number' => '+919876543210']);
        $token = $user->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->postJson('/api/user/profile/phone/verify', [
                'phone_number' => '+919876543210',
                'code' => '123456',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('phone_number');

        $this->assertNull($user->fresh()->phone_number);
    }

    public function test_google_profile_is_incomplete_until_phone_is_verified(): void
    {
        $this->mockVerifiedGoogleToken([
            'sub' => 'google-123',
            'email' => 'alex.google@example.com',
            'email_verified' => true,
            'name' => 'Alex Google',
        ]);

        $response = $this->postJson('/api/auth/google', [
            'id_token' => 'verified-test-token',
        ]);

        $response->assertOk()
            ->assertJsonPath('user.phone_number', null)
            ->assertJsonPath('user.profile_complete', false);
    }

    public function test_request_rejects_a_phone_number_outside_e164_format(): void
    {
        $this->postJson('/api/auth/otp/request', [
            'phone_number' => '98765 43210',
        ])->assertUnprocessable();
    }

    /**
     * @param  array<string, mixed>|null  $claims
     */
    private function mockVerifiedGoogleToken(?array $claims): void
    {
        $this->mock(GoogleIdTokenVerifier::class, function (MockInterface $mock) use ($claims): void {
            $mock->shouldReceive('verify')
                ->once()
                ->with('verified-test-token')
                ->andReturn($claims);
        });
    }
}
