<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class AccountController extends Controller
{
    private const MAIN_APP_ROLES = ['homeOwner', 'contractor', 'designer'];

    public function me(Request $request): JsonResponse
    {
        return response()->json($this->userResponse($request));
    }

    public function access(Request $request): JsonResponse
    {
        return response()->json($this->accessResponse($request));
    }

    public function upgrade(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'role' => ['required', 'string', Rule::in(self::MAIN_APP_ROLES)],
            'name' => ['required', 'string', 'max:255'],
            'location' => ['required', 'string', 'max:255'],
        ]);

        $user = DB::transaction(function () use ($request, $validated) {
            $user = $request->user()->newQuery()
                ->whereKey($request->user()->getKey())
                ->lockForUpdate()
                ->firstOrFail();
            $user->forceFill([
                'name' => trim($validated['name']),
                'location' => trim($validated['location']),
                'role' => $validated['role'],
            ])->save();

            return $user->refresh();
        });

        return response()->json([
            'user' => $this->userResponse($request, $user),
            'access' => $this->accessResponse($request, $user),
        ]);
    }

    private function userResponse(Request $request, $user = null): array
    {
        $user ??= $request->user();

        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'phone_number' => $user->phone_number,
            'location' => $user->location,
            'role' => $user->role,
            'community_registered' => $user->communityProfile()->exists(),
            'profile_complete' => filled($user->name)
                && filled($user->location)
                && filled($user->role)
                && filled($user->phone_number),
        ];
    }

    private function accessResponse(Request $request, $user = null): array
    {
        $user ??= $request->user();
        $role = $user->role;
        $canonicalRole = match ($role) {
            'homeowner' => 'homeOwner',
            'architect', 'engineer', 'interiorDesigner' => 'designer',
            default => $role,
        };
        $hasMainAppAccess = in_array($canonicalRole, self::MAIN_APP_ROLES, true);

        return [
            'has_main_app_access' => $hasMainAppAccess,
            'roles' => $hasMainAppAccess ? [$canonicalRole] : [],
        ];
    }
}
