<?php

namespace App\Http\Middleware;

use App\Models\Project;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureProjectIsActive
{
    public function handle(Request $request, Closure $next): Response
    {
        $project = $request->route('project');
        if ($project instanceof Project
            && ($project->trashed() || $project->archived_at !== null)) {
            return new JsonResponse([
                'message' => 'This project is archived or deleted.',
            ], 410);
        }

        return $next($request);
    }
}
