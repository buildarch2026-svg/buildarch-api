<?php

namespace Tests\Feature;

use App\Models\Project;
use App\Models\ProjectInvitation;
use App\Models\ProjectMember;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Crypt;
use Tests\TestCase;

class ProjectInvitationApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_project_owner_can_create_and_list_a_secure_invitation(): void
    {
        $owner = User::factory()->create(['role' => 'homeOwner']);
        $project = $owner->projects()->create([
            'name' => 'Owner project',
            'location' => 'Kochi, Kerala',
            'type' => 'new_construction',
        ]);
        $token = $owner->createToken('test')->plainTextToken;

        $created = $this->withToken($token)
            ->postJson("/api/projects/{$project->id}/invitations", [
                'role' => 'contractor',
            ])
            ->assertCreated()
            ->assertJsonPath('invitation.role', 'contractor')
            ->assertJsonPath('invitation.status', 'pending')
            ->json('invitation');

        $this->assertMatchesRegularExpression('/^[a-f0-9]{64}$/', $created['token']);
        $this->assertSame(
            now()->addDays(7)->toDateString(),
            substr($created['expires_at'], 0, 10),
        );
        $this->assertDatabaseHas('project_invitations', [
            'project_id' => $project->id,
            'role' => 'contractor',
            'token_hash' => hash('sha256', $created['token']),
        ]);
        $invitation = ProjectInvitation::firstOrFail();
        $this->assertNotSame($created['token'], $invitation->token_encrypted);
        $this->assertSame($created['token'], Crypt::decryptString($invitation->token_encrypted));

        $this->withToken($token)
            ->getJson("/api/projects/{$project->id}/invitations")
            ->assertOk()
            ->assertJsonPath('invitations.0.token', $created['token']);
    }

    public function test_only_the_project_owner_can_manage_invitations(): void
    {
        $owner = User::factory()->create();
        $anotherUser = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Private project',
            'location' => 'Kochi, Kerala',
            'type' => 'renovation',
        ]);
        $token = $anotherUser->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->postJson("/api/projects/{$project->id}/invitations", [
                'role' => 'designer',
            ])->assertForbidden();
        $this->withToken($token)
            ->getJson("/api/projects/{$project->id}/invitations")
            ->assertForbidden();
    }

    public function test_invitation_management_requires_authentication(): void
    {
        $owner = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Private project',
            'location' => 'Kochi, Kerala',
            'type' => 'renovation',
        ]);

        $this->postJson("/api/projects/{$project->id}/invitations", [
            'role' => 'designer',
        ])->assertUnauthorized();
    }

    public function test_invitation_role_is_validated_by_the_server(): void
    {
        $owner = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Private project',
            'location' => 'Kochi, Kerala',
            'type' => 'renovation',
        ]);

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/projects/{$project->id}/invitations", [
                'role' => 'homeOwner',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('role');
    }

    public function test_matching_authenticated_member_can_accept_and_access_project(): void
    {
        [$project, $invitation, $rawToken] = $this->createInvitation('designer');
        $member = User::factory()->create(['role' => 'designer']);
        $token = $member->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->getJson("/api/invitations/{$rawToken}")
            ->assertOk()
            ->assertJsonPath('invitation.project.name', 'Invited project')
            ->assertJsonPath('invitation.can_accept', true)
            ->assertJsonPath('invitation.role', 'designer');

        $this->withToken($token)
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertOk()
            ->assertJsonPath('accepted', true)
            ->assertJsonPath('role', 'designer')
            ->assertJsonPath('project_id', $project->id);

        $this->assertDatabaseHas('project_members', [
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'designer',
        ]);
        $this->assertSame('accepted', $invitation->fresh()->status);

        $this->withToken($token)
            ->getJson('/api/projects')
            ->assertOk()
            ->assertJsonCount(1, 'projects')
            ->assertJsonPath('projects.0.name', 'Invited project')
            ->assertJsonPath('projects.0.is_owner', false);

        $this->withToken($token)
            ->getJson("/api/projects/{$project->id}/members")
            ->assertOk()
            ->assertJsonPath('members.0.user_id', $member->id)
            ->assertJsonPath('members.0.role', 'designer')
            ->assertJsonPath('owner.role', 'homeOwner');

        $this->withToken($token)
            ->postJson("/api/projects/{$project->id}/invitations", [
                'role' => 'contractor',
            ])
            ->assertForbidden();
    }

    public function test_non_member_cannot_read_project_members(): void
    {
        $owner = User::factory()->create();
        $outsider = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Private project',
            'location' => 'Kochi, Kerala',
            'type' => 'renovation',
        ]);

        $this->actingAs($outsider, 'sanctum')
            ->getJson("/api/projects/{$project->id}/members")
            ->assertForbidden();
    }

    public function test_invitation_cannot_be_accepted_by_an_account_with_another_role(): void
    {
        [, , $rawToken] = $this->createInvitation('contractor');
        $member = User::factory()->create(['role' => 'designer']);

        $this->actingAs($member, 'sanctum')
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertForbidden();

        $this->assertDatabaseCount('project_members', 0);
    }

    public function test_invitation_cannot_be_accepted_by_its_owner(): void
    {
        [$project, , $rawToken] = $this->createInvitation('contractor');

        $this->actingAs($project->user, 'sanctum')
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertForbidden();
    }

    public function test_expired_invitation_is_marked_and_cannot_be_accepted(): void
    {
        [, $invitation, $rawToken] = $this->createInvitation('contractor');
        $invitation->update(['expires_at' => now()->subSecond()]);
        $member = User::factory()->create(['role' => 'contractor']);

        $this->actingAs($member, 'sanctum')
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertGone();

        $this->assertSame('expired', $invitation->fresh()->status);
        $this->assertDatabaseCount('project_members', 0);
    }

    public function test_revoked_invitation_cannot_be_accepted(): void
    {
        [$project, $invitation, $rawToken] = $this->createInvitation('contractor');
        $ownerToken = $project->user->createToken('owner')->plainTextToken;
        $member = User::factory()->create(['role' => 'contractor']);

        $this->withToken($ownerToken)
            ->postJson(
                "/api/projects/{$project->id}/invitations/{$invitation->id}/revoke",
            )->assertOk();

        $this->withToken($member->createToken('member')->plainTextToken)
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertStatus(409);

        $this->assertDatabaseCount('project_members', 0);
    }

    public function test_declined_invitation_cannot_later_be_accepted(): void
    {
        [, $invitation, $rawToken] = $this->createInvitation('designer');
        $member = User::factory()->create(['role' => 'designer']);
        $token = $member->createToken('member')->plainTextToken;

        $this->withToken($token)
            ->postJson("/api/invitations/{$rawToken}/decline")
            ->assertOk()
            ->assertJsonPath('declined', true);
        $this->withToken($token)
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertStatus(409);

        $this->assertSame('declined', $invitation->fresh()->status);
        $this->assertDatabaseCount('project_members', 0);
    }

    public function test_accepted_invitation_cannot_be_reused_or_duplicate_membership(): void
    {
        [$project, , $firstRawToken] = $this->createInvitation('contractor');
        [, , $secondRawToken] = $this->createInvitation('contractor', $project);
        $member = User::factory()->create(['role' => 'contractor']);
        $token = $member->createToken('member')->plainTextToken;

        $this->withToken($token)
            ->postJson("/api/invitations/{$firstRawToken}/accept")
            ->assertOk();
        $this->withToken($token)
            ->postJson("/api/invitations/{$firstRawToken}/accept")
            ->assertStatus(409);
        $this->withToken($token)
            ->postJson("/api/invitations/{$secondRawToken}/accept")
            ->assertStatus(409);

        $this->assertSame(1, ProjectMember::where('project_id', $project->id)
            ->where('user_id', $member->id)
            ->count());
    }

    public function test_invalid_or_unauthenticated_invitation_access_is_rejected(): void
    {
        $this->getJson('/api/invitations/not-a-valid-token')->assertUnauthorized();

        $user = User::factory()->create(['role' => 'contractor']);
        $this->actingAs($user, 'sanctum')
            ->getJson('/api/invitations/'.str_repeat('a', 64))
            ->assertNotFound();
    }

    public function test_home_owner_role_cannot_be_invited_as_a_project_member(): void
    {
        [, , $rawToken] = $this->createInvitation('contractor');
        $homeOwner = User::factory()->create(['role' => 'homeOwner']);

        $this->actingAs($homeOwner, 'sanctum')
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertForbidden();
    }

    /**
     * @return array{0: Project, 1: ProjectInvitation, 2: string}
     */
    private function createInvitation(string $role, ?Project $project = null): array
    {
        $owner = $project?->user ?? User::factory()->create(['role' => 'homeOwner']);
        $project ??= $owner->projects()->create([
            'name' => 'Invited project',
            'location' => 'Kochi, Kerala',
            'type' => 'new_construction',
        ]);
        $rawToken = bin2hex(random_bytes(32));
        $invitation = $project->invitations()->create([
            'invited_by_user_id' => $owner->id,
            'role' => $role,
            'token_hash' => hash('sha256', $rawToken),
            'token_encrypted' => Crypt::encryptString($rawToken),
            'status' => 'pending',
            'expires_at' => now()->addDays(7),
        ]);

        return [$project, $invitation, $rawToken];
    }
}
