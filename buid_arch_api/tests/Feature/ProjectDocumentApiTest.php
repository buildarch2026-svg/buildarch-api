<?php

namespace Tests\Feature;

use App\Models\ProjectDocument;
use App\Models\ProjectMember;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class ProjectDocumentApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_project_owner_can_upload_pdf_and_members_can_list_and_download_it(): void
    {
        Storage::fake('local');
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

        $upload = $this->actingAs($owner, 'sanctum')
            ->post("/api/projects/{$project->id}/documents", [
                'file' => UploadedFile::fake()->createWithContent(
                    'floor-plan.pdf',
                    '%PDF-1.4 sample',
                ),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('document.name', 'floor-plan.pdf')
            ->assertJsonPath('document.uploaded_by', $owner->name);

        $documentId = $upload->json('document.id');
        $storedDocument = ProjectDocument::findOrFail($documentId);
        Storage::disk('local')->assertExists($storedDocument->path);
        $this->assertStringStartsWith(
            "project-documents/{$project->id}/",
            $storedDocument->path,
        );

        $this->actingAs($member, 'sanctum')
            ->getJson("/api/projects/{$project->id}/documents")
            ->assertOk()
            ->assertJsonCount(1, 'documents')
            ->assertJsonPath('documents.0.name', 'floor-plan.pdf');

        $this->actingAs($member, 'sanctum')
            ->get("/api/projects/{$project->id}/documents/{$documentId}")
            ->assertOk()
            ->assertHeader('content-type', 'application/pdf');
    }

    public function test_project_member_can_upload_files_for_the_owner_to_access(): void
    {
        Storage::fake('local');
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

        $upload = $this->actingAs($member, 'sanctum')
            ->post("/api/projects/{$project->id}/documents", [
                'file' => UploadedFile::fake()->createWithContent(
                    'notes.pdf',
                    '%PDF-1.4 sample',
                ),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('document.name', 'notes.pdf')
            ->assertJsonPath('document.uploaded_by', $member->name);

        $documentId = $upload->json('document.id');
        $this->actingAs($owner, 'sanctum')
            ->getJson("/api/projects/{$project->id}/documents")
            ->assertOk()
            ->assertJsonCount(1, 'documents')
            ->assertJsonPath('documents.0.id', $documentId)
            ->assertJsonPath('documents.0.uploaded_by', $member->name);

        $this->actingAs($owner, 'sanctum')
            ->get("/api/projects/{$project->id}/documents/{$documentId}")
            ->assertOk()
            ->assertHeader('content-type', 'application/pdf');
    }

    public function test_unrelated_user_cannot_upload_project_documents(): void
    {
        $owner = User::factory()->create();
        $otherUser = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Family home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);

        $this->actingAs($otherUser, 'sanctum')
            ->post("/api/projects/{$project->id}/documents", [
                'file' => UploadedFile::fake()->createWithContent(
                    'notes.pdf',
                    '%PDF-1.4 sample',
                ),
            ], ['Accept' => 'application/json'])
            ->assertForbidden();
    }

    public function test_designer_uploads_are_categorized_as_drawings_for_the_project_team(): void
    {
        Storage::fake('local');
        $owner = User::factory()->create();
        $designer = User::factory()->create(['role' => 'designer']);
        $project = $owner->projects()->create([
            'name' => 'Family home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);
        ProjectMember::create([
            'project_id' => $project->id,
            'user_id' => $designer->id,
            'role' => 'designer',
        ]);

        $upload = $this->actingAs($designer, 'sanctum')
            ->post("/api/projects/{$project->id}/documents", [
                'file' => UploadedFile::fake()->createWithContent(
                    'floor-plan.pdf',
                    '%PDF-1.4 sample',
                ),
            ], ['Accept' => 'application/json'])
            ->assertCreated()
            ->assertJsonPath('document.category', 'drawings');
        $documentId = $upload->json('document.id');

        $this->actingAs($owner, 'sanctum')
            ->getJson("/api/projects/{$project->id}/documents")
            ->assertOk()
            ->assertJsonCount(1, 'documents')
            ->assertJsonPath('documents.0.id', $documentId)
            ->assertJsonPath('documents.0.category', 'drawings')
            ->assertJsonPath('documents.0.uploaded_by', $designer->name);
    }

    public function test_project_documents_are_not_visible_to_unrelated_users(): void
    {
        $owner = User::factory()->create();
        $otherUser = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Family home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);

        $this->actingAs($otherUser, 'sanctum')
            ->getJson("/api/projects/{$project->id}/documents")
            ->assertForbidden();
    }

    public function test_project_document_upload_rejects_unsupported_files(): void
    {
        $owner = User::factory()->create();
        $project = $owner->projects()->create([
            'name' => 'Family home',
            'location' => 'Kochi',
            'type' => 'renovation',
        ]);

        $this->actingAs($owner, 'sanctum')
            ->post("/api/projects/{$project->id}/documents", [
                'file' => UploadedFile::fake()->createWithContent(
                    'notes.txt',
                    'not a supported file',
                ),
            ], ['Accept' => 'application/json'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['file']);
    }
}
