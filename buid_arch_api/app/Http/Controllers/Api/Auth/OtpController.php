<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\OtpChallenge;
use App\Models\User;
use App\Services\GoogleIdentityVerificationUnavailable;
use App\Services\GoogleIdTokenVerifier;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

class OtpController extends Controller
{
    public function send(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'phone_number' => ['required', 'string', 'regex:/^\+[1-9]\d{7,14}$/'],
        ]);

        return $this->createOtpChallenge($validated['phone_number']);
    }

    public function sendProfilePhoneOtp(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'phone_number' => [
                'required',
                'string',
                'regex:/^\+[1-9]\d{7,14}$/',
                Rule::unique('users', 'phone_number')->ignore($request->user()->id),
            ],
        ]);

        return $this->createOtpChallenge($validated['phone_number']);
    }

    private function createOtpChallenge(string $phoneNumber): JsonResponse
    {
        // This temporary sender is only for local development.
        if (! app()->environment('local')) {
            return response()->json([
                'message' => 'WhatsApp delivery is not configured.',
            ], 503);
        }

        $code = (string) random_int(100000, 999999);

        OtpChallenge::where('phone_number', $phoneNumber)->delete();

        OtpChallenge::create([
            'phone_number' => $phoneNumber,
            'code_hash' => Hash::make($code),
            'attempts' => 0,
            'expires_at' => now()->addMinutes(5),
        ]);

        Log::info('Local development OTP', [
            'phone_number' => $phoneNumber,
            'code' => $code,
        ]);

        return response()->json([
            'message' => 'Test code created. Check the Laravel log.',
            'expires_in' => 300,
        ]);
    }

    public function verify(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'phone_number' => ['required', 'string', 'regex:/^\+[1-9]\d{7,14}$/'],
            'code' => ['required', 'digits:6'],
        ]);

        return $this->verifyChallenge(
            $validated['phone_number'],
            $validated['code'],
            function () use ($validated): JsonResponse {
                $user = User::firstOrCreate(
                    ['phone_number' => $validated['phone_number']],
                    [
                        'name' => 'Build Arch User',
                        'email' => null,
                        'password' => Hash::make(Str::random(32)),
                    ],
                );

                $token = $user->createToken('mobile-app')->plainTextToken;

                return response()->json([
                    'verified' => true,
                    'message' => 'Phone number verified.',
                    'token' => $token,
                    'user' => [
                        'id' => $user->id,
                        'name' => $user->name,
                        'phone_number' => $user->phone_number,
                        'email' => $user->email,
                        'location' => $user->location,
                        'role' => $user->role,
                        'profile_complete' => filled($user->name)
                            && filled($user->location)
                            && filled($user->role)
                            && filled($user->phone_number),
                    ],
                ]);
            },
        );
    }

    public function verifyProfilePhone(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'phone_number' => [
                'required',
                'string',
                'regex:/^\+[1-9]\d{7,14}$/',
                Rule::unique('users', 'phone_number')->ignore($request->user()->id),
            ],
            'code' => ['required', 'digits:6'],
        ]);

        return $this->verifyChallenge(
            $validated['phone_number'],
            $validated['code'],
            function () use ($request, $validated): JsonResponse {
                $user = $request->user();
                $user->phone_number = $validated['phone_number'];
                $user->save();

                return response()->json([
                    'verified' => true,
                    'phone_number' => $user->phone_number,
                ]);
            },
        );
    }

    private function verifyChallenge(
        string $phoneNumber,
        string $code,
        Closure $onVerified,
    ): JsonResponse {
        return DB::transaction(function () use ($phoneNumber, $code, $onVerified): JsonResponse {
            $challenge = OtpChallenge::where('phone_number', $phoneNumber)
                ->where('expires_at', '>', now())
                ->latest('id')
                ->lockForUpdate()
                ->first();

            if (! $challenge) {
                return response()->json([
                    'message' => 'Code is invalid or expired.',
                ], 422);
            }

            if ($challenge->attempts >= 5) {
                $challenge->delete();

                return response()->json([
                    'message' => 'Too many attempts. Request a new code.',
                ], 429);
            }

            $challenge->attempts++;
            $challenge->save();

            if (! Hash::check($code, $challenge->code_hash)) {
                return response()->json([
                    'message' => 'Code is incorrect.',
                ], 422);
            }

            $challenge->delete();

            return $onVerified();
        });
    }

    public function google(
        Request $request,
        GoogleIdTokenVerifier $googleIdTokenVerifier,
    ): JsonResponse {
        $validated = $request->validate([
            'id_token' => ['required', 'string', 'max:8192'],
        ]);

        try {
            $googleUser = $googleIdTokenVerifier->verify($validated['id_token']);
        } catch (GoogleIdentityVerificationUnavailable $exception) {
            report($exception);

            return response()->json([
                'message' => 'Google sign-in is temporarily unavailable.',
            ], 503);
        }

        if ($googleUser === null) {
            return response()->json([
                'message' => 'The Google sign-in token is invalid or expired.',
            ], 401);
        }

        $googleId = $googleUser['sub'];
        $email = $googleUser['email'];
        $name = $googleUser['name'] ?? null;
        if (! is_string($name) || trim($name) === '') {
            $name = Str::before($email, '@');
        }

        $user = User::where('google_id', $googleId)->first();

        if (! $user) {
            $user = User::where('email', $email)->first();
        }

        if (! $user) {
            $user = User::create([
                'name' => $name,
                'email' => $email,
                'google_id' => $googleId,
                'password' => Hash::make(Str::random(32)),
            ]);
        } else {
            $user->update([
                'name' => $name,
                'email' => $email,
                'google_id' => $googleId,
            ]);
        }

        $token = $user->createToken('google-app')->plainTextToken;

        return response()->json([
            'verified' => true,
            'message' => 'Google account verified.',
            'token' => $token,
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'google_id' => $user->google_id,
                'location' => $user->location,
                'role' => $user->role,
                'profile_complete' => filled($user->name)
                    && filled($user->location)
                    && filled($user->role)
                    && filled($user->phone_number),
                'phone_number' => $user->phone_number,
            ],
        ]);
    }
}
