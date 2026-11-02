<?php

namespace Tests\Feature;

use App\Models\Project;
use App\Models\ProjectInvitation;
use App\Models\ProjectMember;
use App\Models\ProjectTransaction;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ProjectLifecycleApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_owner_can_edit_archive_and_restore_a_project(): void
    {
        $owner = User::factory()->create(['role' => 'homeOwner']);
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $this->createProject($owner);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'contractor',
        ]);
        $ownerToken = $owner->createToken('test')->plainTextToken;
        $memberToken = $member->createToken('test')->plainTextToken;

        $this->withFreshToken($ownerToken)
            ->patchJson("/api/projects/{$project->id}", [
                'name' => 'Updated home',
                'location' => 'Kochi, Kerala',
                'type' => 'renovation',
                'latitude' => null,
                'longitude' => null,
            ])
            ->assertOk()
            ->assertJsonPath('project.name', 'Updated home')
            ->assertJsonPath('project.type', 'renovation');

        $this->withFreshToken($ownerToken)
            ->postJson("/api/projects/{$project->id}/archive")
            ->assertOk()
            ->assertJsonPath('project.is_archived', true);

        $this->withFreshToken($memberToken)
            ->getJson("/api/projects/{$project->id}/members")
            ->assertStatus(410);

        $this->withFreshToken($ownerToken)
            ->getJson('/api/projects')
            ->assertOk()
            ->assertJsonPath('projects.0.is_archived', true);

        $this->withFreshToken($ownerToken)
            ->postJson("/api/projects/{$project->id}/restore")
            ->assertOk()
            ->assertJsonPath('project.is_archived', false)
            ->assertJsonPath('project.is_deleted', false);

        $this->withFreshToken($memberToken)
            ->getJson("/api/projects/{$project->id}/members")
            ->assertOk();
    }

    public function test_project_delete_is_recoverable_and_retains_membership(): void
    {
        $owner = User::factory()->create(['role' => 'homeOwner']);
        $member = User::factory()->create(['role' => 'designer']);
        $project = $this->createProject($owner);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'designer',
        ]);
        $transaction = ProjectTransaction::create([
            'project_id' => $project->id,
            'payer_user_id' => $owner->id,
            'payee_name' => 'Material supplier',
            'amount' => 1250,
            'currency' => 'INR',
            'status' => 'completed',
        ]);
        $ownerToken = $owner->createToken('test')->plainTextToken;
        $memberToken = $member->createToken('test')->plainTextToken;

        $this->withFreshToken($ownerToken)
            ->deleteJson("/api/projects/{$project->id}")
            ->assertOk()
            ->assertJsonPath('project.is_deleted', true);

        $this->assertSoftDeleted('projects', ['id' => $project->id]);
        $this->assertDatabaseHas('project_members', [
            'project_id' => $project->id,
            'user_id' => $member->id,
        ]);
        $this->assertDatabaseHas('project_transactions', [
            'id' => $transaction->id,
            'project_id' => $project->id,
        ]);

        $this->withFreshToken($ownerToken)
            ->getJson('/api/projects')
            ->assertOk()
            ->assertJsonCount(0, 'projects');

        $memberProjects = $this->withFreshToken($memberToken)
            ->getJson('/api/projects')
            ->assertOk();
        $this->assertSame([], $memberProjects->json('projects'));

        $this->withFreshToken($ownerToken)
            ->postJson("/api/projects/{$project->id}/restore")
            ->assertOk()
            ->assertJsonPath('project.is_deleted', false);

        $this->assertNotSoftDeleted('projects', ['id' => $project->id]);
        $this->withFreshToken($ownerToken)
            ->getJson('/api/projects')
            ->assertOk()
            ->assertJsonCount(1, 'projects');
        $this->withFreshToken($memberToken)
            ->getJson('/api/projects')
            ->assertOk()
            ->assertJsonCount(1, 'projects');
    }

    public function test_archived_projects_do_not_allow_invitation_access_or_acceptance(): void
    {
        $owner = User::factory()->create(['role' => 'homeOwner']);
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $this->createProject($owner);
        $rawToken = str_repeat('a', 64);
        ProjectInvitation::create([
            'project_id' => $project->id,
            'invited_by_user_id' => $owner->id,
            'role' => 'contractor',
            'invitee_name' => 'Test Member',
            'invitee_designation' => 'Contractor',
            'token_hash' => hash('sha256', $rawToken),
            'token_encrypted' => 'encrypted-token',
            'status' => 'pending',
            'expires_at' => now()->addDay(),
        ]);
        $this->withFreshToken($owner->createToken('test')->plainTextToken)
            ->postJson("/api/projects/{$project->id}/archive")
            ->assertOk();

        $memberToken = $member->createToken('test')->plainTextToken;
        $this->withFreshToken($memberToken)
            ->getJson("/api/invitations/{$rawToken}")
            ->assertStatus(410);
        $this->withFreshToken($memberToken)
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertStatus(410);

        $this->assertDatabaseMissing('project_members', [
            'project_id' => $project->id,
            'user_id' => $member->id,
        ]);
    }

    public function test_only_the_owner_can_edit_or_delete_a_project(): void
    {
        $owner = User::factory()->create(['role' => 'homeOwner']);
        $outsider = User::factory()->create(['role' => 'homeOwner']);
        $project = $this->createProject($owner);
        $outsiderToken = $outsider->createToken('test')->plainTextToken;

        $this->withFreshToken($outsiderToken)
            ->patchJson("/api/projects/{$project->id}", ['name' => 'Not allowed'])
            ->assertForbidden();

        $this->withFreshToken($outsiderToken)
            ->deleteJson("/api/projects/{$project->id}")
            ->assertForbidden();
    }

    public function test_project_owner_can_remove_a_member_and_removed_user_loses_access(): void
    {
        $owner = User::factory()->create(['role' => 'homeOwner']);
        $member = User::factory()->create(['role' => 'contractor']);
        $outsider = User::factory()->create(['role' => 'homeOwner']);
        $project = $this->createProject($owner);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'contractor',
        ]);
        $ownerToken = $owner->createToken('test')->plainTextToken;
        $memberToken = $member->createToken('test')->plainTextToken;
        $outsiderToken = $outsider->createToken('test')->plainTextToken;

        $this->withFreshToken($outsiderToken)
            ->deleteJson("/api/projects/{$project->id}/members/{$member->id}")
            ->assertForbidden();

        $removeResponse = $this->withFreshToken($ownerToken)
            ->deleteJson("/api/projects/{$project->id}/members/{$member->id}");
        $removeResponse->assertOk()
            ->assertJsonPath('message', 'Project member removed.');

        $this->assertDatabaseMissing('project_members', [
            'project_id' => $project->id,
            'user_id' => $member->id,
        ]);

        $this->withFreshToken($memberToken)
            ->getJson("/api/projects/{$project->id}/members")
            ->assertForbidden();
    }

    private function createProject(User $owner): Project
    {
        return $owner->projects()->create([
            'name' => 'Home project',
            'location' => 'Kochi',
            'type' => 'new_construction',
        ]);
    }

    private function withFreshToken(string $token): static
    {
        $this->app['auth']->forgetGuards();

        return $this->withToken($token);
    }
}
