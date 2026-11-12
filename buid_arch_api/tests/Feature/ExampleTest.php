<?php

namespace Tests\Feature;

// use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ExampleTest extends TestCase
{
    /**
     * A basic test example.
     */
    public function test_the_application_returns_a_successful_response(): void
    {
        $response = $this->get('/');

        $response->assertStatus(200);
    }

    public function test_public_ping_endpoint_is_available_without_authentication(): void
    {
        $this->getJson('/api/public/ping')
            ->assertOk()
            ->assertSeeText('Hi')
            ->assertHeader('Content-Type', 'text/plain; charset=UTF-8');
    }
}
