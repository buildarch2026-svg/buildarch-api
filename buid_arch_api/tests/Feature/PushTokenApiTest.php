<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\UserPushToken;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class PushTokenApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_users_can_register_and_remove_only_their_push_tokens(): void
    {
        $firstUser = User::factory()->create();
        $secondUser = User::factory()->create();
        $firebaseToken = 'fcm-device-token-0123456789abcdef';
        $tokenHash = hash('sha256', $firebaseToken);

        $this->actingAs($firstUser, 'sanctum')
            ->postJson('/api/push-tokens', [
                'token' => $firebaseToken,
                'platform' => 'android',
            ])
            ->assertCreated()
            ->assertJson(['registered' => true])
            ->assertJsonMissing(['token' => $firebaseToken]);

        $storedToken = UserPushToken::query()->firstOrFail();
        $this->assertSame($firebaseToken, $storedToken->token);
        $this->assertNotSame(
            $firebaseToken,
            DB::table('user_push_tokens')->value('token'),
        );

        $this->actingAs($secondUser, 'sanctum')
            ->postJson('/api/push-tokens', [
                'token' => $firebaseToken,
                'platform' => 'ios',
            ])
            ->assertCreated();

        $this->assertDatabaseCount('user_push_tokens', 1);
        $this->assertDatabaseHas('user_push_tokens', [
            'user_id' => $secondUser->id,
            'token_hash' => $tokenHash,
            'platform' => 'ios',
        ]);

        $this->actingAs($firstUser, 'sanctum')
            ->deleteJson('/api/push-tokens', ['token' => $firebaseToken])
            ->assertOk();
        $this->assertDatabaseCount('user_push_tokens', 1);

        $this->actingAs($secondUser, 'sanctum')
            ->deleteJson('/api/push-tokens', ['token' => $firebaseToken])
            ->assertOk();
        $this->assertDatabaseCount('user_push_tokens', 0);
    }

    public function test_push_token_endpoints_require_authentication_and_validate_platform(): void
    {
        $this->postJson('/api/push-tokens', [
            'token' => 'fcm-device-token-0123456789abcdef',
            'platform' => 'android',
        ])->assertUnauthorized();

        $user = User::factory()->create();
        $this->actingAs($user, 'sanctum')
            ->postJson('/api/push-tokens', [
                'token' => 'fcm-device-token-0123456789abcdef',
                'platform' => 'desktop',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('platform');
    }
}
