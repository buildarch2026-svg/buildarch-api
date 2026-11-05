<?php

namespace Tests\Feature;

use App\Jobs\SendFirebasePushNotification;
use App\Models\ProjectMember;
use App\Models\User;
use App\Models\UserPushToken;
use App\Services\FirebaseMessagingAccessTokenProvider;
use App\Services\FirebasePushService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Queue;
use Tests\TestCase;

class FirebasePushServiceTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_chat_push_is_queued_only_when_server_credentials_are_configured(): void
    {
        Queue::fake();
        $user = User::factory()->create();
        $service = app(FirebasePushService::class);
        $service->queue($user, $this->payload());
        Queue::assertNothingPushed();

        $credentialsFile = tempnam(sys_get_temp_dir(), 'firebase-test-');
        $this->assertNotFalse($credentialsFile);
        file_put_contents($credentialsFile, '{}');
        config([
            'services.firebase.project_id' => 'build-arch-test',
            'services.firebase.credentials' => $credentialsFile,
        ]);

        try {
            $service->queue($user, $this->payload());
            Queue::assertPushed(
                SendFirebasePushNotification::class,
                fn (SendFirebasePushNotification $job) => $job->userId === $user->id,
            );
        } finally {
            unlink($credentialsFile);
        }
    }

    public function test_firebase_push_sends_only_to_registered_device_tokens(): void
    {
        $credentialsFile = tempnam(sys_get_temp_dir(), 'firebase-test-');
        $this->assertNotFalse($credentialsFile);
        file_put_contents($credentialsFile, '{}');
        config([
            'services.firebase.project_id' => 'build-arch-test',
            'services.firebase.credentials' => $credentialsFile,
        ]);

        try {
            $user = User::factory()->create();
            $firebaseToken = 'fcm-device-token-0123456789abcdef';
            UserPushToken::query()->create([
                'user_id' => $user->id,
                'token_hash' => hash('sha256', $firebaseToken),
                'token' => $firebaseToken,
                'platform' => 'android',
            ]);

            $this->mock(FirebaseMessagingAccessTokenProvider::class)
                ->shouldReceive('fetch')
                ->once()
                ->andReturn([
                    'access_token' => 'test-google-access-token',
                    'expires_in' => 3600,
                ]);
            Http::fake([
                'https://fcm.googleapis.com/*' => Http::response(
                    ['name' => 'projects/build-arch-test/messages/test-id'],
                    200,
                ),
            ]);

            app(FirebasePushService::class)->sendToUser(
                $user->id,
                $this->payload(),
            );

            Http::assertSent(function (Request $request) use ($firebaseToken) {
                return $request->url()
                    === 'https://fcm.googleapis.com/v1/projects/build-arch-test/messages:send'
                    && $request->hasHeader(
                        'Authorization',
                        'Bearer test-google-access-token',
                    )
                    && $request['message']['token'] === $firebaseToken
                    && $request['message']['notification']['title'] === 'New project message'
                    && $request['message']['data']['conversation_type'] === 'group';
            });
        } finally {
            unlink($credentialsFile);
        }
    }

    public function test_direct_and_group_messages_queue_pushes_for_other_members(): void
    {
        $credentialsFile = tempnam(sys_get_temp_dir(), 'firebase-test-');
        $this->assertNotFalse($credentialsFile);
        file_put_contents($credentialsFile, '{}');
        config([
            'services.firebase.project_id' => 'build-arch-test',
            'services.firebase.credentials' => $credentialsFile,
        ]);
        Queue::fake();

        try {
            $owner = User::factory()->create(['name' => 'Project Owner']);
            $firstMember = User::factory()->create(['role' => 'designer']);
            $secondMember = User::factory()->create(['role' => 'contractor']);
            $project = $owner->projects()->create([
                'name' => 'Push test project',
                'location' => 'Kochi',
                'type' => 'renovation',
            ]);
            foreach ([$firstMember, $secondMember] as $member) {
                ProjectMember::create([
                    'project_id' => $project->id,
                    'user_id' => $member->id,
                    'role' => $member->role,
                ]);
                UserPushToken::query()->create([
                    'user_id' => $member->id,
                    'token_hash' => hash('sha256', "device-token-{$member->id}"),
                    'token' => "device-token-{$member->id}",
                    'platform' => 'android',
                ]);
            }
            UserPushToken::query()->create([
                'user_id' => $owner->id,
                'token_hash' => hash('sha256', 'device-token-owner'),
                'token' => 'device-token-owner',
                'platform' => 'android',
            ]);

            $this->actingAs($owner, 'sanctum')
                ->postJson(
                    "/api/projects/{$project->id}/members/{$firstMember->id}/messages",
                    ['body' => 'A direct message'],
                )
                ->assertCreated();
            Queue::assertPushed(
                SendFirebasePushNotification::class,
                fn (SendFirebasePushNotification $job) => $job->userId === $firstMember->id
                    && $job->payload['data']['conversation_type'] === 'direct',
            );

            $this->actingAs($firstMember, 'sanctum')
                ->postJson(
                    "/api/projects/{$project->id}/group-chat/messages",
                    ['body' => 'A group message'],
                )
                ->assertCreated();
            Queue::assertPushed(
                SendFirebasePushNotification::class,
                fn (SendFirebasePushNotification $job) => $job->userId === $owner->id
                    && $job->payload['data']['conversation_type'] === 'group',
            );
            Queue::assertPushed(
                SendFirebasePushNotification::class,
                fn (SendFirebasePushNotification $job) => $job->userId === $secondMember->id
                    && $job->payload['data']['conversation_type'] === 'group',
            );
            Queue::assertPushed(
                SendFirebasePushNotification::class,
                fn (SendFirebasePushNotification $job) => $job->userId === $firstMember->id
                    && $job->payload['data']['conversation_type'] === 'direct',
                1,
            );
        } finally {
            unlink($credentialsFile);
        }
    }

    private function payload(): array
    {
        return [
            'title' => 'New project message',
            'body' => 'A team member sent a message.',
            'data' => [
                'event' => 'chat_message',
                'project_id' => '7',
                'conversation_type' => 'group',
            ],
        ];
    }
}
