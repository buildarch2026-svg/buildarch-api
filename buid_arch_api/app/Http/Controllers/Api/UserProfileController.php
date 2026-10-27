<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class UserProfileController extends Controller
{
  public function update(Request $request): JsonResponse
  {
    $validated = $request->validate([
      'name' => ['required', 'string', 'max:255'],
      'location' => ['required', 'string', 'max:255'],
      'role' => [
        'required',
        Rule::in(['homeOwner', 'contractor', 'designer']),
      ],
    ]);

    $user = $request->user();
    $user->update($validated);

    return response()->json([
      'user' => [
        'id' => $user->id,
        'name' => $user->name,
        'email' => $user->email,
        'phone_number' => $user->phone_number,
        'location' => $user->location,
        'role' => $user->role,
      ],
    ]);
  }
}
