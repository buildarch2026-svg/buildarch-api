<?php

namespace Tests\Feature;

use App\Models\CommunityContactRequest;
use App\Models\CommunityLike;
use App\Models\CommunityPost;
use App\Models\CommunityProfile;
use App\Models\CommunityReport;
use App\Models\User;
use App\Services\FirebasePushService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class CommunityApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_all_existing_roles_can_register_once_without_changing_their_project_role(): void
    {
        foreach (['homeowner', 'designer', 'contractor'] as $role) {
            $user = User::factory()->create([
                'name' => ucfirst($role).' User',
                'role' => $role,
            ]);

            $this->actingAs($user, 'sanctum')
                ->getJson('/api/community/profile')
                ->assertOk()
                ->assertJsonPath('registered', false)
                ->assertJsonPath('profile', null);

            $this->postJson('/api/community/profile', [
                'display_name' => $user->name,
                'profession' => 'Other',
                'other_profession' => 'Building enthusiast',
                'bio' => 'Learning and sharing.',
                'guidelines_accepted' => true,
            ])->assertCreated()
                ->assertJsonPath('profile.display_name', $user->name)
                ->assertJsonPath('profile.profession_type', 'Other')
                ->assertJsonPath('profile.profession', 'Building enthusiast');

            $this->postJson('/api/community/profile', [
                'display_name' => $user->name,
                'profession' => 'Homeowner',
                'guidelines_accepted' => true,
            ])->assertConflict();

            $this->assertSame($role, $user->fresh()->role);
            $this->assertSame(1, CommunityProfile::where('user_id', $user->id)->count());
        }
    }

    public function test_community_requires_authentication_and_valid_registration_data(): void
    {
        $this->getJson('/api/community/feed')->assertUnauthorized();

        $user = User::factory()->create();
        $this->actingAs($user, 'sanctum')
            ->postJson('/api/community/profile', [
                'display_name' => 'Member',
                'profession' => 'Other',
                'guidelines_accepted' => false,
            ])->assertUnprocessable()
            ->assertJsonValidationErrors(['other_profession', 'guidelines_accepted']);

        $this->getJson('/api/community/feed')
            ->assertConflict()
            ->assertJsonPath('message', 'Complete Community registration first.');
    }

    public function test_community_registration_allows_an_optional_profession(): void
    {
        $user = User::factory()->create(['role' => null]);

        $this->actingAs($user, 'sanctum')
            ->postJson('/api/community/register', [
                'display_name' => 'Community Member',
                'location' => 'Kochi, Kerala',
                'guidelines_accepted' => true,
            ])
            ->assertCreated()
            ->assertJsonPath('profile.profession', 'Community member')
            ->assertJsonPath('profile.profession_type', null)
            ->assertJsonPath('profile.location', 'Kochi, Kerala');

        $this->assertDatabaseHas('community_profiles', [
            'user_id' => $user->id,
            'profession' => null,
            'location' => 'Kochi, Kerala',
        ]);
    }

    public function test_multipart_community_registration_persists_display_name_and_location_with_profile_image(): void
    {
        Storage::fake('local');
        $user = User::factory()->create(['role' => null]);

        $response = $this->actingAs($user, 'sanctum')
            ->post('/api/community/profile', [
                'display_name' => 'Malu',
                'location' => 'Kochi, Kerala',
                'guidelines_accepted' => '1',
                'profile_image' => UploadedFile::fake()->image('profile.jpg'),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('profile.display_name', 'Malu')
            ->assertJsonPath('profile.location', 'Kochi, Kerala');

        $this->assertDatabaseHas('community_profiles', [
            'user_id' => $user->id,
            'display_name' => 'Malu',
            'location' => 'Kochi, Kerala',
        ]);
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'name' => 'Malu',
            'location' => 'Kochi, Kerala',
        ]);
        Storage::disk('local')->assertExists(
            CommunityProfile::query()
                ->where('user_id', $user->id)
                ->value('profile_image_path'),
        );
        $this->assertSame(
            'Malu',
            CommunityProfile::findOrFail($response->json('profile.id'))->display_name,
        );
        $this->actingAs($user, 'sanctum')
            ->getJson('/api/community/profile')
            ->assertOk()
            ->assertJsonPath('profile.display_name', 'Malu')
            ->assertJsonPath('profile.location', 'Kochi, Kerala');
        $this->getJson('/api/me')
            ->assertOk()
            ->assertJsonPath('name', 'Malu')
            ->assertJsonPath('location', 'Kochi, Kerala');
    }

    public function test_editing_community_name_and_location_updates_the_user_record(): void
    {
        $user = User::factory()->create([
            'name' => 'Original Name',
            'location' => 'Original Location',
            'role' => null,
        ]);
        $profile = $this->register($user);

        $this->actingAs($user, 'sanctum')
            ->patchJson('/api/community/profile', [
                'display_name' => 'Updated Community Name',
                'location' => 'Chennai, Tamil Nadu',
            ])
            ->assertOk()
            ->assertJsonPath('profile.display_name', 'Updated Community Name')
            ->assertJsonPath('profile.location', 'Chennai, Tamil Nadu');

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'name' => 'Updated Community Name',
            'location' => 'Chennai, Tamil Nadu',
        ]);
        $this->assertDatabaseHas('community_profiles', [
            'id' => $profile->id,
            'display_name' => 'Updated Community Name',
            'location' => 'Chennai, Tamil Nadu',
        ]);
    }

    public function test_migration_backfills_existing_community_identity_to_users(): void
    {
        $userWithLocation = User::factory()->create([
            'name' => 'Old Name',
            'location' => 'Old Location',
        ]);
        $profileWithLocation = CommunityProfile::query()->create([
            'user_id' => $userWithLocation->id,
            'display_name' => 'Community Name',
            'profession' => null,
            'location' => 'Community Location',
            'guidelines_accepted_at' => now(),
        ]);
        $userWithoutCommunityLocation = User::factory()->create([
            'name' => 'Another Old Name',
            'location' => 'Keep Existing Location',
        ]);
        CommunityProfile::query()->create([
            'user_id' => $userWithoutCommunityLocation->id,
            'display_name' => 'Another Community Name',
            'profession' => null,
            'location' => null,
            'guidelines_accepted_at' => now(),
        ]);

        $migration = require database_path(
            'migrations/2026_11_15_000001_sync_community_identity_to_users.php',
        );
        $migration->up();

        $this->assertDatabaseHas('users', [
            'id' => $userWithLocation->id,
            'name' => 'Community Name',
            'location' => 'Community Location',
        ]);
        $this->assertDatabaseHas('users', [
            'id' => $userWithoutCommunityLocation->id,
            'name' => 'Another Community Name',
            'location' => 'Keep Existing Location',
        ]);
        $this->assertDatabaseHas('community_profiles', [
            'id' => $profileWithLocation->id,
            'display_name' => 'Community Name',
            'location' => 'Community Location',
        ]);
    }

    public function test_member_phone_is_only_returned_to_an_accepted_contact(): void
    {
        $author = User::factory()->create([
            'phone_number' => '+919876543210',
            'role' => null,
        ]);
        $viewer = User::factory()->create(['role' => null]);
        $authorProfile = $this->register($author);
        $this->register($viewer);
        $profileUrl = "/api/community/profiles/{$authorProfile->id}";

        $this->actingAs($viewer, 'sanctum')
            ->getJson($profileUrl)
            ->assertOk()
            ->assertJsonMissingPath('profile.phone_number');

        $this->actingAs($author, 'sanctum')
            ->patchJson('/api/community/profile', ['is_phone_visible' => true])
            ->assertOk()
            ->assertJsonPath('profile.is_phone_visible', true);
        $authorProfile->posts()->create([
            'content' => 'Community post',
            'status' => 'published',
        ]);

        $this->actingAs($viewer, 'sanctum')
            ->getJson($profileUrl)
            ->assertOk()
            ->assertJsonMissingPath('profile.phone_number');
        $this->getJson('/api/community/feed')
            ->assertOk()
            ->assertJsonMissingPath('posts.data.0.author.phone_number');

        $unregisteredViewer = User::factory()->create(['role' => null]);
        $this->actingAs($unregisteredViewer, 'sanctum')
            ->getJson($profileUrl)
            ->assertConflict();

        $memberWithoutPhone = User::factory()->create([
            'phone_number' => null,
            'role' => null,
        ]);
        $profileWithoutPhone = $this->register($memberWithoutPhone);
        $this->actingAs($memberWithoutPhone, 'sanctum')
            ->patchJson('/api/community/profile', ['is_phone_visible' => true])
            ->assertOk()
            ->assertJsonPath('profile.is_phone_visible', true);
        $this->actingAs($viewer, 'sanctum')
            ->getJson("/api/community/profiles/{$profileWithoutPhone->id}")
            ->assertOk()
            ->assertJsonMissingPath('profile.phone_number');

        $this->actingAs($memberWithoutPhone, 'sanctum')
            ->patchJson('/api/community/profile', ['is_phone_visible' => 'invalid'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['is_phone_visible']);
    }

    public function test_contact_request_acceptance_grants_mutual_phone_access_and_sends_notifications(): void
    {
        $alice = User::factory()->create(['phone_number' => '+919876543210', 'role' => null]);
        $bob = User::factory()->create(['phone_number' => '+919876543211', 'role' => 'designer']);
        $aliceProfile = $this->register($alice, 'Architect');
        $bobProfile = $this->register($bob, 'Contractor');
        $unrelated = User::factory()->create(['role' => null]);
        $this->register($unrelated);

        $push = \Mockery::mock(FirebasePushService::class);
        $push->shouldReceive('queue')->once()
            ->withArgs(fn (User $user, array $payload) => $user->id === $bob->id
                && $payload['data']['notification_type'] === 'community_contact_request'
                && $payload['data']['requester_id'] === (string) $alice->id
                && str_contains($payload['body'], 'Community Member'));
        $push->shouldReceive('queue')->once()
            ->withArgs(fn (User $user, array $payload) => $user->id === $alice->id
                && $payload['data']['notification_type'] === 'community_contact_request_accepted');
        $this->app->instance(FirebasePushService::class, $push);

        $this->getJson('/api/community/contact-requests')->assertUnauthorized();
        $this->postJson('/api/community/contact-requests', ['receiver_id' => $bob->id])
            ->assertUnauthorized();
        $this->actingAs($alice, 'sanctum')
            ->postJson('/api/community/contact-requests', ['receiver_id' => $bob->id])
            ->assertCreated()
            ->assertJsonPath('request.requester.profession', 'Architect')
            ->assertJsonPath('request.receiver.profession', 'Contractor')
            ->assertJsonMissingPath('request.requester.phone_number');
        $request = CommunityContactRequest::query()->firstOrFail();

        $this->postJson('/api/community/contact-requests', ['receiver_id' => $bob->id])
            ->assertOk()
            ->assertJsonPath('request.id', $request->id);
        $this->getJson('/api/community/contact-requests/sent')
            ->assertOk()
            ->assertJsonPath('requests.0.status', 'pending');
        $this->actingAs($bob, 'sanctum')
            ->postJson('/api/community/contact-requests', ['receiver_id' => $alice->id])
            ->assertConflict();
        $this->getJson('/api/community/contact-requests/received')
            ->assertOk()
            ->assertJsonPath('requests.0.requester.display_name', 'Community Member')
            ->assertJsonMissingPath('requests.0.requester.phone_number');
        $this->putJson("/api/community/contact-requests/{$request->id}/accept")
            ->assertOk()
            ->assertJsonPath('request.status', 'accepted');

        $this->actingAs($alice, 'sanctum')
            ->getJson("/api/community/profiles/{$bobProfile->id}")
            ->assertOk()
            ->assertJsonPath('profile.phone_number', '+919876543211');
        $this->actingAs($bob, 'sanctum')
            ->getJson("/api/community/profiles/{$aliceProfile->id}")
            ->assertOk()
            ->assertJsonPath('profile.phone_number', '+919876543210');
        $this->getJson('/api/community/contacts')
            ->assertOk()
            ->assertJsonPath('contacts.0.phone_number', '+919876543210');
        $this->actingAs($alice, 'sanctum')
            ->getJson('/api/community/contacts')
            ->assertOk()
            ->assertJsonPath('contacts.0.phone_number', '+919876543211');
        $this->actingAs($unrelated, 'sanctum')
            ->getJson("/api/community/profiles/{$bobProfile->id}")
            ->assertOk()
            ->assertJsonMissingPath('profile.phone_number');
        $this->actingAs($alice, 'sanctum')
            ->getJson("/api/community/members/{$bob->id}/contact-status")
            ->assertOk()
            ->assertJsonPath('status', 'accepted');
    }

    public function test_rejected_and_cancelled_requests_enforce_ownership_and_revoke_phone_access(): void
    {
        $alice = User::factory()->create(['phone_number' => '+14155552671', 'role' => null]);
        $bob = User::factory()->create(['phone_number' => '+14155552672', 'role' => null]);
        $aliceProfile = $this->register($alice);
        $bobProfile = $this->register($bob);
        $push = \Mockery::mock(FirebasePushService::class);
        $push->shouldReceive('queue')->twice()->withArgs(
            fn (User $user, array $payload) => $user->id === $bob->id
                && $payload['data']['notification_type'] === 'community_contact_request',
        );
        $push->shouldReceive('queue')->once()->withArgs(
            fn (User $user, array $payload) => $user->id === $alice->id
                && $payload['data']['notification_type'] === 'community_contact_request_rejected',
        );
        $this->app->instance(FirebasePushService::class, $push);

        $this->actingAs($alice, 'sanctum')
            ->postJson('/api/community/contact-requests', ['receiver_id' => $bob->id])
            ->assertCreated();
        $request = CommunityContactRequest::query()->firstOrFail();
        $this->actingAs($bob, 'sanctum');
        $this->deleteJson("/api/community/contact-requests/{$request->id}/cancel")
            ->assertForbidden();
        $this->actingAs($alice, 'sanctum');
        $this->deleteJson("/api/community/contact-requests/{$request->id}/cancel")
            ->assertOk();
        $this->assertDatabaseHas('community_contact_requests', [
            'id' => $request->id,
            'status' => 'cancelled',
            'active_pair_key' => null,
        ]);
        $this->postJson('/api/community/contact-requests', ['receiver_id' => $bob->id])
            ->assertCreated();
        $request = CommunityContactRequest::query()->latest('id')->firstOrFail();
        $this->actingAs($alice, 'sanctum')
            ->putJson("/api/community/contact-requests/{$request->id}/reject")
            ->assertForbidden();
        $this->actingAs($bob, 'sanctum')
            ->putJson("/api/community/contact-requests/{$request->id}/reject")
            ->assertOk()
            ->assertJsonPath('request.status', 'rejected');
        $this->actingAs($alice, 'sanctum')
            ->postJson('/api/community/contact-requests', ['receiver_id' => $bob->id])
            ->assertConflict();
        $this->getJson("/api/community/profiles/{$aliceProfile->id}")
            ->assertOk()
            ->assertJsonMissingPath('profile.phone_number');
        $this->getJson("/api/community/profiles/{$bobProfile->id}")
            ->assertOk()
            ->assertJsonMissingPath('profile.phone_number');
    }

    public function test_revocation_and_blocking_immediately_remove_mutual_phone_access(): void
    {
        $alice = User::factory()->create(['phone_number' => '+14155552671', 'role' => null]);
        $bob = User::factory()->create(['phone_number' => '+14155552672', 'role' => null]);
        $aliceProfile = $this->register($alice);
        $bobProfile = $this->register($bob);
        $push = \Mockery::mock(FirebasePushService::class);
        $push->shouldReceive('queue')->twice()->withArgs(
            fn (User $user, array $payload) => $user->id === $bob->id
                && $payload['data']['notification_type'] === 'community_contact_request',
        );
        $push->shouldReceive('queue')->once()->withArgs(
            fn (User $user, array $payload) => $user->id === $alice->id
                && $payload['data']['notification_type'] === 'community_contact_request_accepted',
        );
        $push->shouldReceive('queue')->once()->withArgs(
            fn (User $user, array $payload) => $user->id === $alice->id
                && $payload['data']['notification_type'] === 'community_contact_permission_revoked',
        );
        $this->app->instance(FirebasePushService::class, $push);
        $this->actingAs($alice, 'sanctum')
            ->postJson('/api/community/contact-requests', ['receiver_id' => $bob->id])
            ->assertCreated();
        $request = CommunityContactRequest::query()->firstOrFail();
        $this->actingAs($bob, 'sanctum')
            ->putJson("/api/community/contact-requests/{$request->id}/accept")
            ->assertOk();
        $this->deleteJson("/api/community/contacts/{$alice->id}")
            ->assertOk();
        $this->getJson("/api/community/profiles/{$bobProfile->id}")
            ->assertOk()
            ->assertJsonMissingPath('profile.phone_number');
        $this->getJson("/api/community/profiles/{$aliceProfile->id}")
            ->assertOk()
            ->assertJsonMissingPath('profile.phone_number');
        $this->actingAs($alice, 'sanctum');
        $this->getJson("/api/community/members/{$bob->id}/contact-status")
            ->assertOk()
            ->assertJsonPath('status', 'revoked');
        $this->postJson('/api/community/contact-requests', ['receiver_id' => $bob->id])
            ->assertCreated();
        $this->postJson("/api/community/blocks/{$bob->id}")
            ->assertOk()
            ->assertJsonPath('blocked', true);
        $blockedRequest = CommunityContactRequest::query()->latest('id')->firstOrFail();
        $this->actingAs($bob, 'sanctum')
            ->putJson("/api/community/contact-requests/{$blockedRequest->id}/accept")
            ->assertForbidden();
        $this->actingAs($alice, 'sanctum');
        $this->getJson("/api/community/members/{$bob->id}/contact-status")
            ->assertOk()
            ->assertJsonPath('status', 'blocked');
        $this->postJson('/api/community/contact-requests', ['receiver_id' => $bob->id])
            ->assertForbidden();
        $this->deleteJson("/api/community/blocks/{$bob->id}")
            ->assertOk()
            ->assertJsonPath('blocked', false);
    }

    public function test_feed_is_paginated_category_filtered_and_shows_public_member_content(): void
    {
        $author = User::factory()->create(['role' => 'designer']);
        $viewer = User::factory()->create(['role' => 'contractor']);
        $authorProfile = $this->register($author, 'Architect');
        $viewerProfile = $this->register($viewer, 'Contractor');
        $category = $this->actingAs($viewer, 'sanctum')
            ->getJson('/api/community/categories')
            ->assertOk()
            ->assertJsonCount(8, 'categories')
            ->json('categories.0');

        $post = $authorProfile->posts()->create([
            'content' => 'How do you plan a small home?',
            'community_category_id' => $category['id'],
            'status' => 'published',
        ]);
        for ($index = 0; $index < 16; $index++) {
            $authorProfile->posts()->create([
                'community_category_id' => $category['id'],
                'content' => "Construction discussion {$index}",
                'status' => 'published',
            ]);
        }

        $this->actingAs($viewer, 'sanctum')
            ->getJson('/api/community/feed?category='.$category['slug'])
            ->assertOk()
            ->assertJsonCount(15, 'posts.data')
            ->assertJsonPath('posts.data.0.author.display_name', 'Community Member')
            ->assertJsonPath('posts.data.0.author.profession', 'Architect')
            ->assertJsonPath('posts.data.0.liked_by_me', false)
            ->assertJsonPath('posts.per_page', 15);

        $this->assertSame('Contractor', $viewerProfile->profession);
        $this->assertGreaterThan(0, $post->id);
    }

    public function test_members_can_like_and_unlike_without_duplicate_like_rows(): void
    {
        $author = User::factory()->create();
        $viewer = User::factory()->create();
        $authorProfile = $this->register($author);
        $this->register($viewer);
        $post = $authorProfile->posts()->create([
            'content' => 'A useful building tip',
            'status' => 'published',
        ]);
        $endpoint = "/api/community/posts/{$post->id}/like";

        $this->actingAs($viewer, 'sanctum')
            ->putJson($endpoint)
            ->assertOk()
            ->assertJsonPath('liked', true)
            ->assertJsonPath('likes_count', 1);
        $this->putJson($endpoint)
            ->assertOk()
            ->assertJsonPath('liked', false)
            ->assertJsonPath('likes_count', 0);
        $this->assertSame(0, CommunityLike::where('community_post_id', $post->id)->count());
    }

    public function test_comments_support_single_level_replies_and_only_authors_can_delete_them(): void
    {
        $author = User::factory()->create();
        $commenter = User::factory()->create();
        $other = User::factory()->create();
        $post = $this->register($author)->posts()->create([
            'content' => 'Question about roof materials',
            'status' => 'published',
        ]);
        $this->register($commenter);
        $this->register($other);
        $endpoint = "/api/community/posts/{$post->id}/comments";

        $comment = $this->actingAs($commenter, 'sanctum')
            ->postJson($endpoint, ['content' => 'What is the climate like?'])
            ->assertCreated()
            ->json('comment');
        $reply = $this->postJson($endpoint, [
            'content' => 'It rains heavily here.',
            'parent_comment_id' => $comment['id'],
        ])->assertCreated()
            ->json('comment');

        $this->postJson($endpoint, [
            'content' => 'Nested replies are not supported.',
            'parent_comment_id' => $reply['id'],
        ])->assertUnprocessable();

        $this->actingAs($other, 'sanctum')
            ->deleteJson("{$endpoint}/{$comment['id']}")
            ->assertForbidden();
        $this->actingAs($commenter, 'sanctum')
            ->getJson($endpoint)
            ->assertOk()
            ->assertJsonCount(1, 'comments.data')
            ->assertJsonCount(1, 'comments.data.0.replies');
        $this->deleteJson("{$endpoint}/{$comment['id']}")
            ->assertOk();
        $this->assertSoftDeleted('community_comments', ['id' => $comment['id']]);
        $this->assertSoftDeleted('community_comments', ['id' => $reply['id']]);
    }

    public function test_users_cannot_edit_or_delete_other_members_posts(): void
    {
        $author = User::factory()->create();
        $other = User::factory()->create();
        $post = $this->register($author)->posts()->create([
            'content' => 'Original post',
            'status' => 'published',
        ]);
        $this->register($other);
        $endpoint = "/api/community/posts/{$post->id}";

        $this->actingAs($other, 'sanctum')
            ->patchJson($endpoint, ['content' => 'Changed'])
            ->assertForbidden();
        $this->deleteJson($endpoint)->assertForbidden();
        $this->assertDatabaseHas('community_posts', [
            'id' => $post->id,
            'content' => 'Original post',
        ]);
    }

    public function test_posts_support_private_image_upload_and_authenticated_image_delivery(): void
    {
        Storage::fake('local');
        $author = User::factory()->create();
        $profile = $this->register($author, 'Designer');
        $response = $this->actingAs($author, 'sanctum')
            ->post('/api/community/posts', [
                'content' => 'A material sample',
                'image' => UploadedFile::fake()->image('sample.png'),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('post.author.display_name', 'Community Member');
        $post = CommunityPost::findOrFail($response->json('post.id'));
        Storage::disk('local')->assertExists($post->image_path);
        $this->get("/api/community/media/posts/{$post->id}")
            ->assertOk()
            ->assertHeader('x-content-type-options', 'nosniff');
        $this->assertNotNull($profile->fresh());
    }

    public function test_posts_accept_and_deliver_multiple_images(): void
    {
        Storage::fake('local');
        $author = User::factory()->create();
        $this->register($author, 'Designer');

        $response = $this->actingAs($author, 'sanctum')
            ->post('/api/community/posts', [
                'content' => 'A post with several images',
                'images' => [
                    UploadedFile::fake()->image('first.png'),
                    UploadedFile::fake()->image('second.png'),
                ],
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonCount(2, 'post.image_urls');

        $post = CommunityPost::findOrFail($response->json('post.id'));
        $this->assertCount(2, $post->image_paths);
        foreach ($post->image_paths as $path) {
            Storage::disk('local')->assertExists($path);
        }
        $this->get("/api/community/media/posts/{$post->id}/1")->assertOk();
        $this->get("/api/community/media/posts/{$post->id}/2")->assertOk();
        $this->get("/api/community/media/posts/{$post->id}/3")->assertNotFound();
    }

    public function test_reported_content_can_only_be_reviewed_by_configured_moderators(): void
    {
        $author = User::factory()->create();
        $reporter = User::factory()->create();
        $moderator = User::factory()->create();
        $post = $this->register($author)->posts()->create([
            'content' => 'Potentially misleading claim',
            'status' => 'published',
        ]);
        $this->register($reporter);
        $this->register($moderator);
        config(['community.moderator_user_ids' => [$moderator->id]]);

        $this->actingAs($reporter, 'sanctum')
            ->postJson('/api/community/reports', [
                'target_type' => 'post',
                'target_id' => $post->id,
                'reason' => 'misinformation',
                'details' => 'Please review this claim.',
            ])->assertCreated()
            ->json();
        $reportId = CommunityReport::firstOrFail()->id;

        $this->postJson('/api/community/reports', [
            'target_type' => 'post',
            'target_id' => $post->id,
            'reason' => 'spam',
        ])->assertConflict();
        $this->getJson('/api/community/moderation/reports')->assertForbidden();
        $this->actingAs($moderator, 'sanctum')
            ->getJson('/api/community/moderation/reports')
            ->assertOk()
            ->assertJsonPath('reports.data.0.id', $reportId)
            ->assertJsonPath('reports.data.0.content', 'Potentially misleading claim');
        $this->patchJson("/api/community/moderation/reports/{$reportId}", [
            'action' => 'hide',
        ])->assertOk();

        $this->assertDatabaseHas('community_posts', [
            'id' => $post->id,
            'status' => 'hidden',
        ]);
        $this->getJson('/api/community/feed')->assertOk()->assertJsonCount(0, 'posts.data');
        $this->assertDatabaseHas('community_reports', [
            'id' => $reportId,
            'reason' => 'misinformation',
            'status' => 'reviewed',
        ]);
    }

    private function register(User $user, string $profession = 'Homeowner'): CommunityProfile
    {
        $profile = CommunityProfile::query()->create([
            'user_id' => $user->id,
            'display_name' => 'Community Member',
            'profession' => $profession,
            'guidelines_accepted_at' => now(),
        ]);

        return $profile;
    }
}
