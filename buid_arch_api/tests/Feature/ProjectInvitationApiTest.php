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

    public function test_project_owner_can_create_and_list_a_general_invitation(): void
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
                'invitee_name' => 'Rahul Menon',
                'invitee_designation' => 'Site Engineer',
            ])
            ->assertCreated()
            ->assertJsonPath('invitation.role', 'general')
            ->assertJsonPath('invitation.invitee_name', 'Rahul Menon')
            ->assertJsonPath('invitation.invitee_designation', 'Site Engineer')
            ->assertJsonPath('invitation.status', 'pending')
            ->json('invitation');

        $this->assertMatchesRegularExpression('/^[a-f0-9]{64}$/', $created['token']);
        $this->assertSame(
            now()->addDays(7)->toDateString(),
            substr($created['expires_at'], 0, 10),
        );
        $this->assertDatabaseHas('project_invitations', [
            'project_id' => $project->id,
            'role' => 'general',
            'invitee_name' => 'Rahul Menon',
            'invitee_designation' => 'Site Engineer',
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
                'invitee_name' => 'Test User',
                'invitee_designation' => 'Contractor',
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
            'invitee_name' => 'Test User',
            'invitee_designation' => 'Designer',
        ])->assertUnauthorized();
    }

    public function test_invitation_name_and_designation_are_validated_by_the_server(): void
    {
        $owner = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Private project',
            'location' => 'Kochi, Kerala',
            'type' => 'renovation',
        ]);

        $this->actingAs($owner, 'sanctum')
            ->postJson("/api/projects/{$project->id}/invitations", [
                'invitee_designation' => 'Site Engineer',
            ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('invitee_name');
    }

    public function test_any_authenticated_non_member_can_accept_a_general_invitation(): void
    {
        [$project, $invitation, $rawToken] = $this->createInvitation();
        $member = User::factory()->create(['role' => 'designer']);
        $token = $member->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->getJson("/api/invitations/{$rawToken}")
            ->assertOk()
            ->assertJsonPath('invitation.project.name', 'Invited project')
            ->assertJsonPath('invitation.can_accept', true)
            ->assertJsonPath('invitation.invitee_name', 'Rahul Menon');

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
            'display_name' => 'Rahul Menon',
            'designation' => 'Site Engineer',
        ]);
        $this->assertSame('designer', $member->fresh()->role);
        $this->assertSame($member->name, $member->fresh()->name);
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
            ->assertJsonPath('members.0.name', 'Rahul Menon')
            ->assertJsonPath('members.0.designation', 'Site Engineer')
            ->assertJsonPath('members.0.role', 'designer')
            ->assertJsonPath('owner.role', 'homeOwner');
    }

    public function test_project_member_identity_is_scoped_to_each_project(): void
    {
        $member = User::factory()->create(['role' => 'contractor']);
        [$projectOne, , $tokenOne] = $this->createInvitation();
        $projectTwoOwner = User::factory()->create(['role' => 'homeOwner']);
        $projectTwo = $projectTwoOwner->projects()->create([
            'name' => 'Second project',
            'location' => 'Kochi, Kerala',
            'type' => 'renovation',
        ]);
        $tokenTwo = bin2hex(random_bytes(32));
        $projectTwo->invitations()->create([
            'invited_by_user_id' => $projectTwoOwner->id,
            'role' => 'general',
            'invitee_name' => 'Project Two Name',
            'invitee_designation' => 'Project Two Designation',
            'token_hash' => hash('sha256', $tokenTwo),
            'token_encrypted' => Crypt::encryptString($tokenTwo),
            'status' => 'pending',
            'expires_at' => now()->addDays(7),
        ]);
        $token = $member->createToken('test')->plainTextToken;

        $this->withToken($token)
            ->postJson("/api/invitations/{$tokenOne}/accept")
            ->assertOk();
        $this->withToken($token)
            ->postJson("/api/invitations/{$tokenTwo}/accept")
            ->assertOk();

        $this->assertDatabaseHas('project_members', [
            'project_id' => $projectOne->id,
            'user_id' => $member->id,
            'display_name' => 'Rahul Menon',
            'designation' => 'Site Engineer',
        ]);
        $this->assertDatabaseHas('project_members', [
            'project_id' => $projectTwo->id,
            'user_id' => $member->id,
            'display_name' => 'Project Two Name',
            'designation' => 'Project Two Designation',
        ]);
        $this->assertSame('contractor', $member->fresh()->role);
    }

    public function test_existing_project_members_fall_back_to_profile_details(): void
    {
        $owner = User::factory()->create(['role' => 'homeOwner']);
        $member = User::factory()->create([
            'name' => 'Registered Name',
            'role' => 'designer',
        ]);
        $project = $owner->projects()->create([
            'name' => 'Existing team project',
            'location' => 'Kochi, Kerala',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'designer',
        ]);

        $this->withToken($owner->createToken('test')->plainTextToken)
            ->getJson("/api/projects/{$project->id}/members")
            ->assertOk()
            ->assertJsonPath('members.0.name', 'Registered Name')
            ->assertJsonPath('members.0.designation', 'Designer');
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

    public function test_invitation_cannot_be_accepted_by_its_owner(): void
    {
        [$project, , $rawToken] = $this->createInvitation();

        $this->actingAs($project->user, 'sanctum')
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertForbidden();
    }

    public function test_expired_invitation_is_marked_and_cannot_be_accepted(): void
    {
        [, $invitation, $rawToken] = $this->createInvitation();
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
        [$project, $invitation, $rawToken] = $this->createInvitation();
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
        [, $invitation, $rawToken] = $this->createInvitation();
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
        [$project, , $firstRawToken] = $this->createInvitation();
        [, , $secondRawToken] = $this->createInvitation(project: $project);
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

    public function test_owner_invitation_list_contains_only_unexpired_pending_invitations(): void
    {
        [$project, $pendingInvitation] = $this->createInvitation();
        [, $expiredInvitation] = $this->createInvitation(project: $project);
        [, $acceptedInvitation] = $this->createInvitation(project: $project);
        [, $declinedInvitation] = $this->createInvitation(project: $project);
        [, $revokedInvitation] = $this->createInvitation(project: $project);
        [, $removedInvitation] = $this->createInvitation(project: $project);

        $expiredInvitation->update(['expires_at' => now()->subSecond()]);
        $acceptedInvitation->update(['status' => 'accepted']);
        $declinedInvitation->update(['status' => 'declined']);
        $revokedInvitation->update(['status' => 'revoked']);
        $removedInvitation->update(['status' => 'removed']);
        $ownerToken = $project->user->createToken('owner')->plainTextToken;

        $response = $this->withToken($ownerToken)
            ->getJson("/api/projects/{$project->id}/invitations")
            ->assertOk()
            ->assertJsonCount(1, 'invitations')
            ->assertJsonPath('invitations.0.id', $pendingInvitation->id)
            ->assertJsonPath('invitations.0.status', 'pending');

        $this->assertSame('expired', $expiredInvitation->fresh()->status);
        $this->assertSame(
            [$pendingInvitation->id],
            array_column($response->json('invitations'), 'id'),
        );
    }

    public function test_removing_member_deactivates_membership_and_preserves_invitation_history(): void
    {
        [$project, $acceptedInvitation, $rawToken] = $this->createInvitation();
        [, $pendingInvitation] = $this->createInvitation(project: $project);
        $removedUser = User::factory()->create(['role' => 'contractor']);
        $otherMember = User::factory()->create(['role' => 'designer']);
        $ownerToken = $project->user->createToken('owner')->plainTextToken;
        $removedUserToken = $removedUser->createToken('member')->plainTextToken;

        $this->withFreshToken($removedUserToken)
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertOk();
        $acceptedAt = $acceptedInvitation->fresh()->accepted_at;
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $otherMember->id,
            'role' => 'designer',
        ]);

        $removalResponse = $this->withFreshToken($ownerToken)
            ->deleteJson("/api/projects/{$project->id}/members/{$removedUser->id}");
        $this->assertSame(200, $removalResponse->status(), $removalResponse->getContent());

        $this->assertDatabaseMissing('project_members', [
            'project_id' => $project->id,
            'user_id' => $removedUser->id,
        ]);
        $this->assertDatabaseHas('project_invitations', [
            'id' => $acceptedInvitation->id,
            'status' => 'removed',
            'accepted_by_user_id' => $removedUser->id,
        ]);
        $this->assertNotNull($acceptedInvitation->fresh()->removed_at);
        $this->assertSame($acceptedAt->toDateTimeString(), $acceptedInvitation->fresh()->accepted_at->toDateTimeString());
        $this->assertSame($removedUser->name, $removedUser->fresh()->name);

        $this->withFreshToken($ownerToken)
            ->getJson("/api/projects/{$project->id}/members")
            ->assertOk()
            ->assertJsonCount(1, 'members')
            ->assertJsonPath('members.0.user_id', $otherMember->id);
        $this->withFreshToken($ownerToken)
            ->getJson("/api/projects/{$project->id}/invitations")
            ->assertOk()
            ->assertJsonCount(1, 'invitations')
            ->assertJsonPath('invitations.0.id', $pendingInvitation->id);

        $this->withFreshToken($removedUserToken)
            ->postJson("/api/invitations/{$rawToken}/accept")
            ->assertStatus(409);

        [, , $newRawToken] = $this->createInvitation(project: $project);
        $this->withFreshToken($removedUserToken)
            ->postJson("/api/invitations/{$newRawToken}/accept")
            ->assertOk();

        $this->assertDatabaseHas('project_members', [
            'project_id' => $project->id,
            'user_id' => $removedUser->id,
        ]);
        $this->assertSame('removed', $acceptedInvitation->fresh()->status);
    }

    public function test_invalid_or_unauthenticated_invitation_access_is_rejected(): void
    {
        $this->getJson('/api/invitations/not-a-valid-token')->assertUnauthorized();

        $user = User::factory()->create(['role' => 'contractor']);
        $this->actingAs($user, 'sanctum')
            ->getJson('/api/invitations/'.str_repeat('a', 64))
            ->assertNotFound();
    }

    /**
     * @return array{0: Project, 1: ProjectInvitation, 2: string}
     */
    private function createInvitation(?Project $project = null): array
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
            'role' => 'general',
            'invitee_name' => 'Rahul Menon',
            'invitee_designation' => 'Site Engineer',
            'token_hash' => hash('sha256', $rawToken),
            'token_encrypted' => Crypt::encryptString($rawToken),
            'status' => 'pending',
            'expires_at' => now()->addDays(7),
        ]);

        return [$project, $invitation, $rawToken];
    }

    private function withFreshToken(string $token): static
    {
        $this->app['auth']->forgetGuards();

        return $this->withToken($token);
    }
}
