<?php

namespace Tests\Feature;

use App\Models\ProjectConversation;
use App\Models\ProjectGroupMessage;
use App\Models\ProjectMember;
use App\Models\ProjectMessage;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class ProjectMessageApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_project_owner_and_member_can_exchange_private_messages(): void
    {
        $owner = User::factory()->create(['name' => 'Home Owner']);
        $member = User::factory()->create([
            'name' => 'Project Designer',
            'role' => 'designer',
        ]);
        $project = $owner->projects()->create([
            'name' => 'Shared home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'designer',
        ]);
        $endpoint = "/api/projects/{$project->id}/members/{$member->id}/messages";

        $ownerMessage = $this->actingAs($owner, 'sanctum')
            ->postJson($endpoint, ['body' => 'Can we review the drawings?'])
            ->assertCreated()
            ->assertJsonPath('message.sender_user_id', $owner->id)
            ->assertJsonPath('message.sender_name', 'Home Owner')
            ->json('message');

        $this->actingAs($member, 'sanctum')
            ->postJson($endpoint, ['body' => 'Yes, I will share them today.'])
            ->assertCreated()
            ->assertJsonPath('message.sender_user_id', $member->id);

        $this->actingAs($member, 'sanctum')
            ->postJson("{$endpoint}/read")
            ->assertOk();

        $this->actingAs($member, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonCount(2, 'messages')
            ->assertJsonPath('messages.0.id', $ownerMessage['id'])
            ->assertJsonPath('messages.0.body', 'Can we review the drawings?')
            ->assertJsonPath('messages.1.body', 'Yes, I will share them today.');

        $this->actingAs($owner, 'sanctum')
            ->getJson($endpoint.'?after_id='.$ownerMessage['id'])
            ->assertOk()
            ->assertJsonCount(1, 'messages')
            ->assertJsonPath('messages.0.body', 'Yes, I will share them today.')
            ->assertJsonPath('messages.0.read_by_user_ids', []);

        $this->actingAs($owner, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonPath('messages.0.read_by_user_ids', [$member->id]);
    }

    public function test_project_messages_require_a_conversation_participant(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create(['role' => 'contractor']);
        $otherMember = User::factory()->create(['role' => 'designer']);
        $outsider = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Shared home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        foreach ([$member, $otherMember] as $projectMember) {
            ProjectMember::create([
                'project_id' => $project->id,
                'user_id' => $projectMember->id,
                'role' => $projectMember->role,
            ]);
        }
        $endpoint = "/api/projects/{$project->id}/members/{$member->id}/messages";

        $this->withToken($otherMember->createToken('test')->plainTextToken)
            ->getJson($endpoint)
            ->assertForbidden();

        $this->withToken($outsider->createToken('test')->plainTextToken)
            ->getJson($endpoint)
            ->assertForbidden();
    }

    public function test_private_chat_files_are_visible_only_to_their_participants(): void
    {
        Storage::fake('local');
        $owner = User::factory()->create(['name' => 'Home Owner']);
        $firstMember = User::factory()->create(['name' => 'Designer', 'role' => 'designer']);
        $secondMember = User::factory()->create(['name' => 'Contractor', 'role' => 'contractor']);
        $outsider = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Shared home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        foreach ([$firstMember, $secondMember] as $member) {
            ProjectMember::create([
                'project_id' => $project->id,
                'user_id' => $member->id,
                'role' => $member->role,
            ]);
        }

        $firstChat = "/api/projects/{$project->id}/members/{$firstMember->id}/messages";
        $secondChat = "/api/projects/{$project->id}/members/{$secondMember->id}/messages";
        $firstFileId = $this->actingAs($firstMember, 'sanctum')
            ->post("{$firstChat}/attachments", [
                'message_type' => 'image',
                'file' => UploadedFile::fake()->image('private-design.jpg'),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->json('message.id');
        $secondFileId = $this->actingAs($secondMember, 'sanctum')
            ->post("{$secondChat}/attachments", [
                'message_type' => 'image',
                'file' => UploadedFile::fake()->image('private-site.jpg'),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->json('message.id');

        $filesEndpoint = "/api/projects/{$project->id}/chat/files";
        $this->actingAs($firstMember, 'sanctum')
            ->getJson($filesEndpoint)
            ->assertOk()
            ->assertJsonCount(1, 'files')
            ->assertJsonPath('files.0.id', $firstFileId)
            ->assertJsonPath(
                'files.0.conversation_member.user_id',
                $firstMember->id,
            );
        $this->actingAs($secondMember, 'sanctum')
            ->getJson($filesEndpoint)
            ->assertOk()
            ->assertJsonCount(1, 'files')
            ->assertJsonPath('files.0.id', $secondFileId);
        $this->actingAs($owner, 'sanctum')
            ->getJson($filesEndpoint)
            ->assertOk()
            ->assertJsonCount(2, 'files');
        $this->actingAs($outsider, 'sanctum')
            ->getJson($filesEndpoint)
            ->assertForbidden();
    }

    public function test_project_members_cannot_start_a_conversation_with_each_other(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create(['role' => 'contractor']);
        $otherMember = User::factory()->create(['role' => 'designer']);
        $project = $owner->projects()->create([
            'name' => 'Shared home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        foreach ([$member, $otherMember] as $projectMember) {
            ProjectMember::create([
                'project_id' => $project->id,
                'user_id' => $projectMember->id,
                'role' => $projectMember->role,
            ]);
        }

        $this->withToken($member->createToken('test')->plainTextToken)
            ->postJson(
                "/api/projects/{$project->id}/members/{$otherMember->id}/messages",
                ['body' => 'Hello'],
            )
            ->assertForbidden();
    }

    public function test_project_message_body_is_required_and_limited_to_4000_characters(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Shared home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => $member->role,
        ]);
        $token = $owner->createToken('test')->plainTextToken;
        $endpoint = "/api/projects/{$project->id}/members/{$member->id}/messages";

        $this->withToken($token)
            ->postJson($endpoint, ['body' => '  '])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('body');

        $this->withToken($token)
            ->postJson($endpoint, ['body' => str_repeat('a', 4001)])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('body');
    }

    public function test_project_participants_can_exchange_private_attachments(): void
    {
        Storage::fake('local');
        $owner = User::factory()->create();
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Shared home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => $member->role,
        ]);
        $endpoint = "/api/projects/{$project->id}/members/{$member->id}/messages";

        $response = $this->actingAs($owner, 'sanctum')
            ->postJson("{$endpoint}/attachments", [
                'message_type' => 'file',
                'file' => UploadedFile::fake()->createWithContent(
                    'plans.pdf',
                    "%PDF-1.4\nProject plans",
                ),
            ])
            ->assertCreated()
            ->assertJsonPath('message.message_type', 'file')
            ->assertJsonPath('message.body', null)
            ->assertJsonPath('message.attachment_name', 'plans.pdf');
        $messageId = $response->json('message.id');

        $this->actingAs($member, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonPath('messages.0.id', $messageId)
            ->assertJsonPath('messages.0.attachment_name', 'plans.pdf');

        $this->actingAs($member, 'sanctum')
            ->get("{$endpoint}/{$messageId}/attachment")
            ->assertOk();

        $imageId = $this->actingAs($member, 'sanctum')
            ->postJson("{$endpoint}/attachments", [
                'message_type' => 'image',
                'file' => UploadedFile::fake()->image('progress.jpg'),
            ])
            ->assertCreated()
            ->assertJsonPath('message.message_type', 'image')
            ->assertJsonPath('message.attachment_name', 'progress.jpg')
            ->json('message.id');

        $voiceId = $this->actingAs($owner, 'sanctum')
            ->postJson("{$endpoint}/attachments", [
                'message_type' => 'voice',
                'file' => UploadedFile::fake()->createWithContent(
                    'voice-note.m4a',
                    "\0\0\0\x18ftypM4A \0\0\0\0",
                ),
            ])
            ->assertCreated()
            ->assertJsonPath('message.message_type', 'voice')
            ->assertJsonPath('message.attachment_name', 'voice-note.m4a')
            ->json('message.id');

        $this->actingAs($owner, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonCount(3, 'messages')
            ->assertJsonPath('messages.1.id', $imageId)
            ->assertJsonPath('messages.2.id', $voiceId);

        $this->actingAs($owner, 'sanctum')
            ->get("{$endpoint}/{$imageId}/attachment")
            ->assertOk();

        $outsider = User::factory()->create();
        $this->actingAs($outsider, 'sanctum')
            ->get("{$endpoint}/{$messageId}/attachment")
            ->assertForbidden();
    }

    public function test_project_attachment_type_must_match_the_uploaded_file(): void
    {
        Storage::fake('local');
        $owner = User::factory()->create();
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Shared home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => $member->role,
        ]);
        $endpoint =
            "/api/projects/{$project->id}/members/{$member->id}/messages/attachments";

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
                'The attachment content does not match a supported image, PDF, or voice-note format.',
            );
    }

    public function test_direct_chat_supports_replies_edits_deletes_and_read_state(): void
    {
        $owner = User::factory()->create(['name' => 'Project Owner']);
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Chat interactions',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'contractor',
            'display_name' => 'Site Contractor',
            'designation' => 'Site Lead',
        ]);
        $endpoint = "/api/projects/{$project->id}/members/{$member->id}/messages";

        $original = $this->actingAs($owner, 'sanctum')
            ->postJson($endpoint, ['body' => 'Check the foundation'])
            ->assertCreated()
            ->json('message');

        $reply = $this->actingAs($member, 'sanctum')
            ->postJson($endpoint, [
                'body' => 'I will inspect it.',
                'reply_to_message_id' => $original['id'],
            ])
            ->assertCreated()
            ->assertJsonPath('message.sender_name', 'Site Contractor')
            ->assertJsonPath('message.sender_designation', 'Site Lead')
            ->assertJsonPath('message.reply_to.id', $original['id'])
            ->json('message');

        $edited = $this->actingAs($member, 'sanctum')
            ->patchJson("{$endpoint}/{$reply['id']}", [
                'body' => 'Inspection completed.',
            ])
            ->assertOk()
            ->assertJsonPath('message.body', 'Inspection completed.');
        $this->assertNotNull($edited->json('message.edited_at'));

        $chats = $this->actingAs($owner, 'sanctum')
            ->getJson('/api/chats')
            ->assertOk()
            ->json('chats');
        $directChat = collect($chats)->firstWhere('type', 'direct');
        $this->assertSame(1, $directChat['unread_count']);

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/projects/{$project->id}/members/{$member->id}/messages/read")
            ->assertOk();

        $chats = $this->actingAs($owner, 'sanctum')
            ->getJson('/api/chats')
            ->assertOk()
            ->json('chats');
        $directChat = collect($chats)->firstWhere('type', 'direct');
        $this->assertSame(0, $directChat['unread_count']);

        $this->actingAs($owner, 'sanctum')
            ->deleteJson("{$endpoint}/{$reply['id']}")
            ->assertForbidden();

        $this->actingAs($member, 'sanctum')
            ->deleteJson("{$endpoint}/{$reply['id']}")
            ->assertOk()
            ->assertJsonPath('message.message_type', 'deleted')
            ->assertJsonPath('message.body', null);
    }

    public function test_chat_list_includes_active_project_and_counterpart_metadata(): void
    {
        $owner = User::factory()->create(['name' => 'Home Owner']);
        $member = User::factory()->create(['role' => 'designer']);
        $project = $owner->projects()->create([
            'name' => 'Chat list project',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'designer',
            'display_name' => 'Project Designer',
            'designation' => 'Interior Designer',
        ]);

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/projects/{$project->id}/members/{$member->id}/messages", [
                'body' => 'Welcome to the project.',
            ])
            ->assertCreated();

        $chats = $this->actingAs($owner, 'sanctum')
            ->getJson('/api/chats')
            ->assertOk()
            ->json('chats');
        $direct = collect($chats)->firstWhere(
            'id',
            "direct:{$project->id}:{$member->id}",
        );

        $this->assertNotNull($direct);
        $this->assertSame('Chat list project', $direct['project_name']);
        $this->assertSame('Kochi', $direct['project_location']);
        $this->assertSame('renovation', $direct['project_type']);
        $this->assertTrue($direct['is_owner']);
        $this->assertSame('Project Designer', $direct['name']);
        $this->assertSame($member->id, $direct['counterpart_user_id']);
        $this->assertSame('designer', $direct['counterpart_role']);
        $this->assertSame('Interior Designer', $direct['counterpart_designation']);
    }

    public function test_owner_can_forward_messages_between_project_conversations(): void
    {
        $owner = User::factory()->create(['name' => 'Project Owner']);
        $firstMember = User::factory()->create(['name' => 'Designer']);
        $secondMember = User::factory()->create(['name' => 'Contractor']);
        $project = $owner->projects()->create([
            'name' => 'Forward messages',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        foreach ([$firstMember, $secondMember] as $member) {
            ProjectMember::create([
                'project_id' => $project->id,
                'user_id' => $member->id,
                'role' => 'designer',
            ]);
        }

        $sourceMessage = $this->actingAs($owner, 'sanctum')
            ->postJson(
                "/api/projects/{$project->id}/members/{$firstMember->id}/messages",
                ['body' => 'Please review this plan.'],
            )
            ->assertCreated()
            ->json('message');

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/projects/{$project->id}/chat/forward", [
                'source_type' => 'direct',
                'source_member_user_id' => $firstMember->id,
                'source_message_id' => $sourceMessage['id'],
                'target_type' => 'group',
            ])
            ->assertCreated()
            ->assertJsonPath('message.body', 'Please review this plan.')
            ->assertJsonPath('message.forwarded_from_name', 'Project Owner')
            ->assertJsonPath('message.sender_user_id', $owner->id);

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/projects/{$project->id}/chat/forward", [
                'source_type' => 'direct',
                'source_member_user_id' => $firstMember->id,
                'source_message_id' => $sourceMessage['id'],
                'target_type' => 'direct',
                'target_member_user_id' => $secondMember->id,
            ])
            ->assertCreated()
            ->assertJsonPath('message.forwarded_from_name', 'Project Owner');

        $groupConversation = $project->groupConversation()->firstOrFail();
        $this->assertDatabaseHas('project_group_messages', [
            'conversation_id' => $groupConversation->id,
            'body' => 'Please review this plan.',
            'forwarded_from_name' => 'Project Owner',
        ]);

        $secondConversation = $project->directConversations()
            ->where('member_user_id', $secondMember->id)
            ->firstOrFail();
        $this->assertDatabaseHas('project_messages', [
            'conversation_id' => $secondConversation->id,
            'body' => 'Please review this plan.',
            'forwarded_from_name' => 'Project Owner',
        ]);
    }

    public function test_member_cannot_forward_another_members_private_message(): void
    {
        $owner = User::factory()->create();
        $sender = User::factory()->create();
        $otherMember = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Private forwarding',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        foreach ([$sender, $otherMember] as $member) {
            ProjectMember::create([
                'project_id' => $project->id,
                'user_id' => $member->id,
                'role' => 'designer',
            ]);
        }
        $endpoint = "/api/projects/{$project->id}/members/{$sender->id}/messages";
        $message = $this->actingAs($owner, 'sanctum')
            ->postJson($endpoint, ['body' => 'Private message'])
            ->assertCreated()
            ->json('message');

        $this->actingAs($otherMember, 'sanctum')
            ->postJson("/api/projects/{$project->id}/chat/forward", [
                'source_type' => 'direct',
                'source_member_user_id' => $sender->id,
                'source_message_id' => $message['id'],
                'target_type' => 'group',
            ])
            ->assertForbidden();
    }

    public function test_forwarded_attachments_are_copied_to_the_target_conversation(): void
    {
        Storage::fake('local');
        $owner = User::factory()->create(['name' => 'Project Owner']);
        $member = User::factory()->create(['name' => 'Designer']);
        $project = $owner->projects()->create([
            'name' => 'Forward attachments',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'designer',
        ]);

        $source = $this->actingAs($owner, 'sanctum')
            ->postJson("/api/projects/{$project->id}/group-chat/attachments", [
                'message_type' => 'image',
                'file' => UploadedFile::fake()->image('progress.jpg'),
            ])
            ->assertCreated()
            ->json('message');
        $sourceMessage = ProjectGroupMessage::query()->findOrFail($source['id']);
        $sourcePath = $sourceMessage->attachment_path;
        Storage::disk('local')->assertExists($sourcePath);

        $forwarded = $this->actingAs($owner, 'sanctum')
            ->postJson("/api/projects/{$project->id}/chat/forward", [
                'source_type' => 'group',
                'source_message_id' => $source['id'],
                'target_type' => 'direct',
                'target_member_user_id' => $member->id,
            ])
            ->assertCreated()
            ->assertJsonPath('message.message_type', 'image')
            ->assertJsonPath('message.forwarded_from_name', 'Project Owner')
            ->json('message');

        $forwardedMessage = ProjectMessage::query()->findOrFail($forwarded['id']);
        $forwardedPath = $forwardedMessage->attachment_path;
        $this->assertNotSame($sourcePath, $forwardedPath);
        Storage::disk('local')->assertExists($forwardedPath);

        $this->actingAs($owner, 'sanctum')
            ->deleteJson("/api/projects/{$project->id}/group-chat/messages/{$source['id']}")
            ->assertOk();
        Storage::disk('local')->assertMissing($sourcePath);
        Storage::disk('local')->assertExists($forwardedPath);
    }

    public function test_direct_chat_location_and_older_message_pages_are_available(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create(['role' => 'designer']);
        $project = $owner->projects()->create([
            'name' => 'Direct location chat',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'designer',
        ]);
        $endpoint = "/api/projects/{$project->id}/members/{$member->id}/messages";

        $this->actingAs($member, 'sanctum')
            ->postJson("{$endpoint}/location", [
                'latitude' => 9.9312,
                'longitude' => 76.2673,
                'address' => 'Marine Drive, Kochi',
            ])
            ->assertCreated()
            ->assertJsonPath('message.message_type', 'location')
            ->assertJsonPath('message.location_address', 'Marine Drive, Kochi');

        $conversation = ProjectConversation::query()
            ->where('project_id', $project->id)
            ->firstOrFail();
        for ($index = 0; $index < 105; $index++) {
            $conversation->messages()->create([
                'sender_user_id' => $owner->id,
                'body' => "Message {$index}",
            ]);
        }

        $this->actingAs($owner, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonCount(100, 'messages')
            ->assertJsonPath('has_more', true);

        $this->actingAs($owner, 'sanctum')
            ->getJson("{$endpoint}?before_id=8")
            ->assertOk()
            ->assertJsonCount(7, 'messages')
            ->assertJsonPath('messages.0.id', 1)
            ->assertJsonPath('has_more', false);
    }
}
