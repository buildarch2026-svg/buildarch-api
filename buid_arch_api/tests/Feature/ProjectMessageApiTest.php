<?php

namespace Tests\Feature;

use App\Models\ProjectMember;
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
            ->assertJsonPath('messages.0.body', 'Yes, I will share them today.');
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
}
