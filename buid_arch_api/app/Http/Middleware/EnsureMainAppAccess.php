<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureMainAppAccess
{
    public function handle(Request $request, Closure $next): Response
    {
        $role = match ($request->user()?->role) {
            'homeOwner', 'homeowner', 'contractor', 'designer',
            'architect', 'engineer', 'interiorDesigner' => true,
            default => false,
        };

        abort_unless($role, 403, 'Main App access requires a project role.');

        return $next($request);
    }
}
