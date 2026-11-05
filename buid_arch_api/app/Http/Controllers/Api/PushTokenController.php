<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\UserPushToken;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PushTokenController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'token' => ['required', 'string', 'min:20', 'max:4096'],
            'platform' => ['required', 'in:android,ios'],
        ]);
        $tokenHash = hash('sha256', $validated['token']);

        UserPushToken::query()->updateOrCreate(
            ['token_hash' => $tokenHash],
            [
                'user_id' => $request->user()->id,
                'token' => $validated['token'],
                'platform' => $validated['platform'],
                'last_used_at' => now(),
            ],
        );

        return response()->json(['registered' => true], 201);
    }

    public function destroy(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'token' => ['required', 'string', 'min:20', 'max:4096'],
        ]);

        UserPushToken::query()
            ->where('user_id', $request->user()->id)
            ->where('token_hash', hash('sha256', $validated['token']))
            ->delete();

        return response()->json(['removed' => true]);
    }
}
