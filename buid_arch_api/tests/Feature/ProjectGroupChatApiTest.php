<?php

namespace Tests\Feature;

use App\Models\ProjectGroupConversation;
use App\Models\ProjectMember;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Broadcast;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class ProjectGroupChatApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_project_group_members_can_share_and_download_voice_messages(): void
    {
        Storage::fake('local');
        $owner = User::factory()->create(['name' => 'Home Owner']);
        $designer = User::factory()->create(['name' => 'Designer', 'role' => 'designer']);
        $contractor = User::factory()->create(['name' => 'Contractor', 'role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Shared home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        foreach ([$designer, $contractor] as $member) {
            ProjectMember::create([
                'project_id' => $project->id,
                'user_id' => $member->id,
                'role' => $member->role,
            ]);
        }
        $endpoint = "/api/projects/{$project->id}/group-chat";

        $response = $this->actingAs($designer, 'sanctum')
            ->post("{$endpoint}/voice", [
                'file' => UploadedFile::fake()->createWithContent(
                    'voice-note.m4a',
                    "\0\0\0\x18ftypM4A \0\0\0\0",
                ),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('message.message_type', 'voice')
            ->assertJsonPath('message.sender_name', 'Designer')
            ->assertJsonPath('message.body', null);
        $messageId = $response->json('message.id');

        $this->actingAs($owner, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonCount(1, 'messages')
            ->assertJsonPath('messages.0.id', $messageId)
            ->assertJsonPath('messages.0.attachment_name', 'voice-note.m4a');

        $this->actingAs($contractor, 'sanctum')
            ->getJson("{$endpoint}/files")
            ->assertOk()
            ->assertJsonCount(1, 'files')
            ->assertJsonPath('files.0.id', $messageId)
            ->assertJsonPath('files.0.message_type', 'voice');

        $this->actingAs($contractor, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonPath('messages.0.id', $messageId);

        $this->actingAs($owner, 'sanctum')
            ->get("{$endpoint}/voice/{$messageId}")
            ->assertOk();

        $this->assertDatabaseCount('project_group_conversations', 1);
        $this->assertDatabaseCount('project_group_messages', 1);
        $this->assertDatabaseHas('notifications', [
            'notifiable_id' => $owner->id,
        ]);
        $this->assertDatabaseHas('notifications', [
            'notifiable_id' => $contractor->id,
        ]);
        $this->assertDatabaseMissing('notifications', [
            'notifiable_id' => $designer->id,
        ]);
    }

    public function test_project_members_can_exchange_text_and_image_messages(): void
    {
        Storage::fake('local');
        $owner = User::factory()->create(['name' => 'Home Owner']);
        $member = User::factory()->create(['role' => 'contractor']);
        $otherMember = User::factory()->create(['role' => 'designer']);
        $project = $owner->projects()->create([
            'name' => 'Shared home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'contractor',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $otherMember->id,
            'role' => 'designer',
        ]);
        $endpoint = "/api/projects/{$project->id}/group-chat";

        $textId = $this->actingAs($owner, 'sanctum')
            ->postJson("{$endpoint}/messages", ['body' => 'Welcome to the project group.'])
            ->assertCreated()
            ->assertJsonPath('message.message_type', 'text')
            ->assertJsonPath('message.body', 'Welcome to the project group.')
            ->json('message.id');

        $imageResponse = $this->actingAs($member, 'sanctum')
            ->post("{$endpoint}/attachments", [
                'message_type' => 'image',
                'file' => UploadedFile::fake()->image('progress.jpg'),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('message.message_type', 'image')
            ->assertJsonPath('message.attachment_name', 'progress.jpg');
        $imageId = $imageResponse->json('message.id');

        $this->actingAs($member, 'sanctum')
            ->postJson("{$endpoint}/read")
            ->assertOk();

        $this->actingAs($owner, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonCount(2, 'messages')
            ->assertJsonPath('messages.0.id', $textId)
            ->assertJsonPath('messages.0.body', 'Welcome to the project group.')
            ->assertJsonPath('messages.0.read_by_user_ids', [$member->id])
            ->assertJsonPath('messages.1.id', $imageId)
            ->assertJsonPath('messages.1.message_type', 'image');

        $this->actingAs($member, 'sanctum')
            ->getJson("{$endpoint}/files")
            ->assertOk()
            ->assertJsonCount(1, 'files')
            ->assertJsonPath('files.0.id', $imageId)
            ->assertJsonPath('files.0.message_type', 'image');
        $this->actingAs($otherMember, 'sanctum')
            ->getJson("{$endpoint}/files")
            ->assertOk()
            ->assertJsonCount(1, 'files')
            ->assertJsonPath('files.0.id', $imageId);

        $this->actingAs($owner, 'sanctum')
            ->get("{$endpoint}/attachments/{$imageId}")
            ->assertOk();

        $this->assertDatabaseCount('project_group_messages', 2);
        $this->assertDatabaseHas('notifications', [
            'notifiable_id' => $member->id,
        ]);
    }

    public function test_group_chat_rejects_non_image_files_marked_as_images(): void
    {
        Storage::fake('local');
        $owner = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Shared home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        $endpoint = "/api/projects/{$project->id}/group-chat/attachments";

        $this->actingAs($owner, 'sanctum')
            ->postJson($endpoint, [
                'message_type' => 'image',
                'file' => UploadedFile::fake()->create(
                    'plans.pdf',
                    128,
                    'application/pdf',
                ),
            ])
            ->assertUnprocessable()
            ->assertJsonPath(
                'message',
                'The attachment content does not match the selected message type.',
            );

        $this->assertDatabaseCount('project_group_messages', 0);
    }

    public function test_only_project_members_can_access_group_voice_chat(): void
    {
        $owner = User::factory()->create();
        $outsider = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Private home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        $endpoint = "/api/projects/{$project->id}/group-chat";

        $this->actingAs($outsider, 'sanctum')
            ->getJson($endpoint)
            ->assertForbidden();

        $this->assertDatabaseCount('project_group_conversations', 0);
    }

    public function test_group_messages_support_project_identity_replies_editing_and_deletion(): void
    {
        $owner = User::factory()->create(['name' => 'Owner account']);
        $member = User::factory()->create([
            'name' => 'Global designer name',
            'role' => 'designer',
        ]);
        $project = $owner->projects()->create([
            'name' => 'Identity project',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'designer',
            'display_name' => 'Project-specific designer',
            'designation' => 'Kitchen Designer',
        ]);
        $endpoint = "/api/projects/{$project->id}/group-chat";

        $original = $this->actingAs($owner, 'sanctum')
            ->postJson("{$endpoint}/messages", ['body' => 'Review the plan'])
            ->assertCreated()
            ->json('message');

        $reply = $this->actingAs($member, 'sanctum')
            ->postJson("{$endpoint}/messages", [
                'body' => 'I will update it.',
                'reply_to_message_id' => $original['id'],
            ])
            ->assertCreated()
            ->assertJsonPath('message.sender_name', 'Project-specific designer')
            ->assertJsonPath('message.sender_designation', 'Kitchen Designer')
            ->assertJsonPath('message.reply_to.id', $original['id'])
            ->json('message');

        $edited = $this->actingAs($member, 'sanctum')
            ->patchJson("{$endpoint}/messages/{$reply['id']}", [
                'body' => 'I updated it.',
            ])
            ->assertOk()
            ->assertJsonPath('message.body', 'I updated it.');
        $this->assertNotNull($edited->json('message.edited_at'));

        $this->actingAs($owner, 'sanctum')
            ->deleteJson("{$endpoint}/messages/{$reply['id']}")
            ->assertOk()
            ->assertJsonPath('message.message_type', 'deleted')
            ->assertJsonPath('message.body', null);

        $this->actingAs($owner, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonCount(2, 'messages')
            ->assertJsonPath('messages.1.message_type', 'deleted')
            ->assertJsonPath('messages.1.body', null);
    }

    public function test_group_chat_paginates_history_and_records_shared_locations(): void
    {
        $owner = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Location project',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        $endpoint = "/api/projects/{$project->id}/group-chat";
        $this->actingAs($owner, 'sanctum')
            ->postJson("{$endpoint}/location", [
                'latitude' => 9.9312,
                'longitude' => 76.2673,
                'address' => 'Marine Drive, Kochi',
            ])
            ->assertCreated()
            ->assertJsonPath('message.message_type', 'location')
            ->assertJsonPath('message.location_address', 'Marine Drive, Kochi');

        $conversation = ProjectGroupConversation::query()
            ->where('project_id', $project->id)
            ->firstOrFail();
        for ($index = 0; $index < 105; $index++) {
            $conversation->messages()->create([
                'sender_user_id' => $owner->id,
                'body' => "Message {$index}",
                'message_type' => 'text',
            ]);
        }

        $this->actingAs($owner, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonCount(100, 'messages')
            ->assertJsonPath('has_more', true);

        $this->actingAs($owner, 'sanctum')
            ->getJson($endpoint.'?before_id=8')
            ->assertOk()
            ->assertJsonCount(7, 'messages')
            ->assertJsonPath('messages.0.id', 1)
            ->assertJsonPath('has_more', false);
    }

    public function test_only_active_project_participants_can_subscribe_to_chat_channels(): void
    {
        $broadcastManager = Broadcast::getFacadeRoot();
        $channels = $broadcastManager->connection()->getChannels();
        config([
            'broadcasting.default' => 'chat-auth-test',
            'broadcasting.connections.chat-auth-test' => [
                'driver' => 'pusher',
                'key' => 'test-key',
                'secret' => 'test-secret',
                'app_id' => 'test-app',
                'options' => [
                    'host' => 'localhost',
                    'port' => 8080,
                    'scheme' => 'http',
                    'useTLS' => false,
                ],
            ],
        ]);
        $broadcastManager->forgetDrivers();
        $testBroadcaster = $broadcastManager->connection();
        foreach ($channels as $pattern => $callback) {
            $testBroadcaster->channel($pattern, $callback);
        }

        $owner = User::factory()->create();
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Private project',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'contractor',
        ]);

        $this->actingAs($member, 'sanctum')
            ->postJson('/api/broadcasting/auth', [
                'socket_id' => '123.456',
                'channel_name' => "private-project-chat.group.{$project->id}",
            ])
            ->assertOk();

        $directChannel = "private-project-chat.direct.{$project->id}.{$member->id}";
        $this->actingAs($owner, 'sanctum')
            ->postJson('/api/broadcasting/auth', [
                'socket_id' => '234.567',
                'channel_name' => $directChannel,
            ])
            ->assertOk();

        $this->actingAs($member, 'sanctum')
            ->postJson('/api/broadcasting/auth', [
                'socket_id' => '456.789',
                'channel_name' => $directChannel,
            ])
            ->assertOk();

        ProjectMember::query()
            ->where('project_id', $project->id)
            ->where('user_id', $member->id)
            ->delete();
        $this->assertDatabaseMissing('project_members', [
            'project_id' => $project->id,
            'user_id' => $member->id,
        ]);

        $this->actingAs($member, 'sanctum')
            ->postJson('/api/broadcasting/auth', [
                'socket_id' => '789.123',
                'channel_name' => "private-project-chat.group.{$project->id}",
            ])
            ->assertForbidden();

        $this->actingAs($owner, 'sanctum')
            ->postJson('/api/broadcasting/auth', [
                'socket_id' => '345.678',
                'channel_name' => $directChannel,
            ])
            ->assertForbidden();
    }
}
