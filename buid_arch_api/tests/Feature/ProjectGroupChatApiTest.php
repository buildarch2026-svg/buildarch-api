<?php

namespace Tests\Feature;

use App\Models\ProjectMember;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
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

        $this->actingAs($owner, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonCount(2, 'messages')
            ->assertJsonPath('messages.0.id', $textId)
            ->assertJsonPath('messages.0.body', 'Welcome to the project group.')
            ->assertJsonPath('messages.1.id', $imageId)
            ->assertJsonPath('messages.1.message_type', 'image');

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
}
