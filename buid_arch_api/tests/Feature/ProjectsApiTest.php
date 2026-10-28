<?php

namespace Tests\Feature;

use App\Models\ProjectMember;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class ProjectsApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_authenticated_user_can_create_and_list_their_projects(): void
    {
        $owner = User::factory()->create();
        $otherUser = User::factory()->create();
        $otherUser->projects()->create([
            'name' => 'Private project',
            'location' => 'Kochi, Kerala',
            'type' => 'renovation',
        ]);

        $response = $this->actingAs($owner, 'sanctum')->postJson('/api/projects', [
            'name' => 'Menon Residence',
            'location' => 'Chennai, Tamil Nadu',
            'latitude' => 13.0827,
            'longitude' => 80.2707,
            'type' => 'new_construction',
        ]);

        $response->assertCreated()
            ->assertJsonPath('project.name', 'Menon Residence')
            ->assertJsonPath('project.location', 'Chennai, Tamil Nadu')
            ->assertJsonPath('project.latitude', 13.0827)
            ->assertJsonPath('project.longitude', 80.2707)
            ->assertJsonPath('project.is_owner', true)
            ->assertJsonPath('project.type', 'new_construction')
            ->assertJsonPath('project.progress', 0);

        $this->getJson('/api/projects')
            ->assertOk()
            ->assertJsonCount(1, 'projects')
            ->assertJsonPath('projects.0.name', 'Menon Residence')
            ->assertJsonPath('projects.0.latitude', 13.0827)
            ->assertJsonPath('projects.0.longitude', 80.2707);

        $this->assertDatabaseHas('projects', [
            'user_id' => $owner->id,
            'name' => 'Menon Residence',
            'latitude' => 13.0827,
            'longitude' => 80.2707,
        ]);
    }

    public function test_project_coordinates_must_be_valid_and_provided_together(): void
    {
        $user = User::factory()->create();

        $this->actingAs($user, 'sanctum')->postJson('/api/projects', [
            'name' => 'Invalid coordinates',
            'location' => 'Chennai, Tamil Nadu',
            'latitude' => 91,
            'type' => 'new_construction',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors(['latitude', 'longitude']);
    }

    public function test_project_creation_requires_authentication(): void
    {
        $this->postJson('/api/projects', [
            'name' => 'Menon Residence',
            'location' => 'Chennai, Tamil Nadu',
            'type' => 'new_construction',
        ])->assertUnauthorized();

        $this->getJson('/api/projects')->assertUnauthorized();
    }

    public function test_project_creation_validates_required_fields_and_type(): void
    {
        $user = User::factory()->create();

        $this->actingAs($user, 'sanctum')->postJson('/api/projects', [
            'name' => '',
            'location' => '',
            'type' => 'unknown',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors(['name', 'location', 'type']);
    }

    public function test_authenticated_user_can_upload_a_project_photo(): void
    {
        Storage::fake('public');
        $user = User::factory()->create();

        $response = $this->actingAs($user, 'sanctum')->post('/api/projects', [
            'name' => 'Garden House',
            'location' => 'Kochi, Kerala',
            'type' => 'new_construction',
            'photo' => UploadedFile::fake()->image('garden-house.jpg'),
        ], ['Accept' => 'application/json']);

        $response->assertCreated()
            ->assertJsonPath('project.name', 'Garden House');

        $imagePath = $response->json('project.image_path');
        $this->assertNotEmpty($imagePath);
        $this->assertStringEndsWith('/storage/'.$imagePath, $response->json('project.photo_url'));
        Storage::disk('public')->assertExists($imagePath);
        $this->assertDatabaseHas('projects', [
            'user_id' => $user->id,
            'image_path' => $imagePath,
        ]);

        $this->actingAs($user, 'sanctum')
            ->getJson('/api/projects')
            ->assertOk()
            ->assertJsonPath('projects.0.image_path', $imagePath)
            ->assertJsonPath('projects.0.photo_url', $response->json('project.photo_url'));
    }

    public function test_project_owner_can_add_and_replace_a_project_photo(): void
    {
        Storage::fake('public');
        $owner = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Garden House',
            'location' => 'Kochi, Kerala',
            'type' => 'new_construction',
        ]);

        $firstResponse = $this->actingAs($owner, 'sanctum')->post(
            "/api/projects/{$project->id}/photo",
            ['photo' => UploadedFile::fake()->image('first.jpg')],
            ['Accept' => 'application/json'],
        );
        $firstResponse->assertOk()
            ->assertJsonPath('project.is_owner', true);
        $firstImagePath = $firstResponse->json('project.image_path');
        Storage::disk('public')->assertExists($firstImagePath);

        $secondResponse = $this->actingAs($owner, 'sanctum')->post(
            "/api/projects/{$project->id}/photo",
            ['photo' => UploadedFile::fake()->image('second.jpg')],
            ['Accept' => 'application/json'],
        );
        $secondResponse->assertOk()
            ->assertJsonPath('project.name', 'Garden House');
        $secondImagePath = $secondResponse->json('project.image_path');

        $this->assertNotSame($firstImagePath, $secondImagePath);
        Storage::disk('public')->assertMissing($firstImagePath);
        Storage::disk('public')->assertExists($secondImagePath);
        $this->assertDatabaseHas('projects', [
            'id' => $project->id,
            'image_path' => $secondImagePath,
        ]);
    }

    public function test_only_the_project_owner_can_update_the_project_photo(): void
    {
        Storage::fake('public');
        $owner = User::factory()->create();
        $member = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Garden House',
            'location' => 'Kochi, Kerala',
            'type' => 'new_construction',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'contractor',
        ]);

        $this->actingAs($member, 'sanctum')->post(
            "/api/projects/{$project->id}/photo",
            ['photo' => UploadedFile::fake()->image('unauthorized.jpg')],
            ['Accept' => 'application/json'],
        )->assertForbidden();

        $this->assertDatabaseHas('projects', [
            'id' => $project->id,
            'image_path' => null,
        ]);
    }

    public function test_joined_project_lists_the_member_role_and_inviter(): void
    {
        $owner = User::factory()->create(['name' => 'Project Owner']);
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Shared project',
            'location' => 'Kochi, Kerala',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'contractor',
        ]);
        $project->invitations()->create([
            'invited_by_user_id' => $owner->id,
            'role' => 'contractor',
            'token_hash' => hash('sha256', 'accepted-invitation'),
            'token_encrypted' => 'encrypted-token',
            'status' => 'accepted',
            'expires_at' => now()->addDay(),
            'accepted_by_user_id' => $member->id,
            'accepted_at' => now(),
        ]);

        $this->actingAs($member, 'sanctum')
            ->getJson('/api/projects')
            ->assertOk()
            ->assertJsonPath('projects.0.is_owner', false)
            ->assertJsonPath('projects.0.member_role', 'contractor')
            ->assertJsonPath('projects.0.invited_by_name', 'Project Owner')
            ->assertJsonMissingPath('projects.0.members')
            ->assertJsonMissingPath('projects.0.invitations');
    }
}
