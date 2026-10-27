<?php

namespace Tests\Feature;

use App\Models\ProjectMember;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class ProjectNotificationsApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_file_upload_notifies_other_project_participants(): void
    {
        Storage::fake('local');
        $owner = User::factory()->create();
        $designer = User::factory()->create(['role' => 'designer']);
        $contractor = User::factory()->create(['role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Family home',
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

        $response = $this->actingAs($designer, 'sanctum')
            ->post("/api/projects/{$project->id}/documents", [
                'file' => UploadedFile::fake()->createWithContent(
                    'floor-plan.pdf',
                    '%PDF-1.4 sample',
                ),
            ], ['Accept' => 'application/json'])
            ->assertCreated();

        foreach ([$owner, $contractor] as $recipient) {
            $this->actingAs($recipient, 'sanctum')
                ->getJson('/api/notifications')
                ->assertOk()
                ->assertJsonPath('unread_count', 1)
                ->assertJsonPath('notifications.0.event', 'file_upload')
                ->assertJsonPath('notifications.0.project_id', $project->id)
                ->assertJsonPath(
                    'notifications.0.related_id',
                    $response->json('document.id'),
                )
                ->assertJsonPath('notifications.0.read', false);
        }

        $this->assertCount(0, $designer->notifications);
    }

    public function test_chat_message_notifies_only_the_other_conversation_participant(): void
    {
        $owner = User::factory()->create(['name' => 'Home Owner']);
        $member = User::factory()->create([
            'name' => 'Project Designer',
            'role' => 'designer',
        ]);
        $project = $owner->projects()->create([
            'name' => 'Family home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'designer',
        ]);

        $this->actingAs($owner, 'sanctum')
            ->postJson(
                "/api/projects/{$project->id}/members/{$member->id}/messages",
                ['body' => 'Please review the new plan.'],
            )
            ->assertCreated();

        $this->actingAs($member, 'sanctum')
            ->getJson('/api/notifications')
            ->assertOk()
            ->assertJsonPath('unread_count', 1)
            ->assertJsonPath('notifications.0.event', 'chat_message')
            ->assertJsonPath('notifications.0.title', 'New message from Home Owner')
            ->assertJsonPath(
                'notifications.0.message',
                'Please review the new plan.',
            );

        $this->assertCount(0, $owner->notifications);
    }

    public function test_notification_read_state_is_private_to_its_recipient(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Family home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'contractor',
        ]);
        $this->actingAs($owner, 'sanctum')
            ->postJson(
                "/api/projects/{$project->id}/members/{$member->id}/messages",
                ['body' => 'A project update.'],
            )
            ->assertCreated();
        $notificationId = $member->notifications()->value('id');

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/notifications/{$notificationId}/read")
            ->assertNotFound();

        $this->actingAs($member, 'sanctum')
            ->postJson("/api/notifications/{$notificationId}/read")
            ->assertOk();
        $this->actingAs($member, 'sanctum')
            ->getJson('/api/notifications')
            ->assertOk()
            ->assertJsonPath('unread_count', 0)
            ->assertJsonPath('notifications.0.read', true);
    }
}
