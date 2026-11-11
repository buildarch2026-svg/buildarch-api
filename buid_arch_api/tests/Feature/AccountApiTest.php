<?php

namespace Tests\Feature;

use App\Models\CommunityProfile;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AccountApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_current_user_and_access_report_community_only_capabilities(): void
    {
        $user = User::factory()->create(['role' => null]);

        $this->actingAs($user, 'sanctum')
            ->getJson('/api/me')
            ->assertOk()
            ->assertJsonPath('id', $user->id)
            ->assertJsonPath('role', null)
            ->assertJsonPath('community_registered', false)
            ->assertJsonMissingPath('password');

        $this->getJson('/api/account/access')
            ->assertOk()
            ->assertJsonPath('has_main_app_access', false)
            ->assertJsonPath('roles', []);
    }

    public function test_upgrade_preserves_the_account_and_existing_community_content(): void
    {
        $user = User::factory()->create([
            'role' => null,
            'location' => null,
            'email' => 'community@example.test',
            'phone_number' => '+919876543210',
        ]);
        $profile = CommunityProfile::query()->create([
            'user_id' => $user->id,
            'display_name' => 'Community Member',
            'profession' => null,
            'guidelines_accepted_at' => now(),
        ]);
        $post = $profile->posts()->create([
            'content' => 'A discussion that must remain after upgrade.',
            'status' => 'published',
        ]);

        $this->actingAs($user, 'sanctum')
            ->postJson('/api/account/upgrade', [
                'role' => 'homeOwner',
                'name' => 'Updated Name',
                'location' => 'Chennai, Tamil Nadu',
            ])
            ->assertOk()
            ->assertJsonPath('user.id', $user->id)
            ->assertJsonPath('user.role', 'homeOwner')
            ->assertJsonPath('access.has_main_app_access', true)
            ->assertJsonPath('access.roles.0', 'homeOwner');

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'email' => 'community@example.test',
            'phone_number' => '+919876543210',
            'role' => 'homeOwner',
        ]);
        $this->assertDatabaseHas('community_profiles', [
            'id' => $profile->id,
            'user_id' => $user->id,
        ]);
        $this->assertDatabaseHas('community_posts', ['id' => $post->id]);
    }

    public function test_upgrade_is_idempotent_and_rejects_unknown_roles(): void
    {
        $user = User::factory()->create([
            'role' => null,
            'location' => null,
        ]);
        $this->actingAs($user, 'sanctum');

        $payload = [
            'role' => 'contractor',
            'name' => $user->name,
            'location' => 'Kochi, Kerala',
        ];
        $this->postJson('/api/account/upgrade', $payload)
            ->assertOk()
            ->assertJsonPath('user.role', 'contractor');
        $this->postJson('/api/account/upgrade', $payload)
            ->assertOk()
            ->assertJsonPath('user.role', 'contractor');
        $this->assertDatabaseCount('users', 1);

        $this->postJson('/api/account/upgrade', [
            ...$payload,
            'role' => 'administrator',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('role');
    }

    public function test_community_only_users_are_blocked_from_project_apis_until_upgrade(): void
    {
        $user = User::factory()->create(['role' => null]);
        $owner = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Private project',
            'location' => 'Chennai, Tamil Nadu',
            'type' => 'new_construction',
        ]);
        $this->actingAs($user, 'sanctum')
            ->getJson('/api/projects')
            ->assertForbidden();

        $this->postJson('/api/account/upgrade', [
            'role' => 'designer',
            'name' => $user->name,
            'location' => 'Chennai, Tamil Nadu',
        ])->assertOk();

        $this->actingAs($user->fresh(), 'sanctum');
        $this->getJson('/api/projects')->assertOk();
        $this->assertDatabaseHas('projects', [
            'id' => $project->id,
            'user_id' => $owner->id,
        ]);
    }
}
