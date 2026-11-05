<?php

namespace Tests\Feature;

use App\Models\ProjectMember;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ProjectTransactionApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_project_member_can_record_a_payment_for_the_project(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Home renovation',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);

        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'contractor',
        ]);

        $response = $this->actingAs($member, 'sanctum')
            ->postJson("/api/projects/{$project->id}/transactions", [
                'payee_name' => 'Build Mart',
                'payee_type' => 'shop',
                'amount' => 1250.5,
                'currency' => 'INR',
                'status' => 'completed',
                'payment_method' => 'UPI',
                'payment_type' => 'manual',
                'description' => 'Cement and sand',
                'category' => 'materials',
            ])
            ->assertCreated();

        $transactionId = $response->json('transaction.id');

        $this->actingAs($owner, 'sanctum')
            ->getJson("/api/projects/{$project->id}/transactions")
            ->assertOk()
            ->assertJsonCount(1, 'transactions')
            ->assertJsonPath('transactions.0.id', $transactionId)
            ->assertJsonPath('transactions.0.payee_name', 'Build Mart')
            ->assertJsonPath('transactions.0.amount', 1250.5);

        $this->assertDatabaseHas('project_transactions', [
            'project_id' => $project->id,
            'payer_user_id' => $member->id,
            'payee_name' => 'Build Mart',
            'currency' => 'INR',
        ]);
    }

    public function test_repeating_an_attempt_id_returns_the_existing_transaction(): void
    {
        $owner = User::factory()->create();
        $member = User::factory()->create(['role' => 'contractor']);
        $project = $owner->projects()->create([
            'name' => 'Home renovation',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $member->id,
            'role' => 'contractor',
        ]);

        $payload = [
            'payee_name' => 'Build Mart',
            'payee_type' => 'shop',
            'amount' => 1250.5,
            'currency' => 'INR',
            'status' => 'pending',
            'payment_method' => 'UPI',
            'payment_type' => 'provider',
            'description' => 'Cement and sand',
            'category' => 'materials',
            'attempt_id' => 'upi-attempt-123',
        ];
        $endpoint = "/api/projects/{$project->id}/transactions";

        $first = $this->actingAs($member, 'sanctum')
            ->postJson($endpoint, $payload)
            ->assertCreated();
        $transactionId = $first->json('transaction.id');

        $this->postJson($endpoint, $payload)
            ->assertOk()
            ->assertJsonPath('transaction.id', $transactionId);

        $this->patchJson("{$endpoint}/{$transactionId}", ['status' => 'completed'])
            ->assertOk();

        $this->postJson($endpoint, $payload)
            ->assertOk()
            ->assertJsonPath('transaction.id', $transactionId)
            ->assertJsonPath('transaction.status', 'completed');

        $this->postJson($endpoint, [...$payload, 'amount' => 1500])
            ->assertStatus(409);

        $this->assertDatabaseCount('project_transactions', 1);
    }

    public function test_non_members_cannot_access_project_transaction_history(): void
    {
        $owner = User::factory()->create();
        $outsider = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Townhouse',
            'location' => 'Thrissur',
            'type' => 'new_construction',
        ]);

        $this->actingAs($outsider, 'sanctum')
            ->getJson("/api/projects/{$project->id}/transactions")
            ->assertForbidden();
    }
}
