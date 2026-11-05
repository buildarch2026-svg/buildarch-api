<?php

namespace App\Services;

use App\Jobs\SendFirebasePushNotification;
use App\Models\User;
use App\Models\UserPushToken;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;
use Throwable;

class FirebasePushService
{
    private ?string $accessToken = null;

    private int $accessTokenExpiresAt = 0;

    public function queue(User $user, array $payload): void
    {
        if (! $user->pushTokens()->exists()) {
            return;
        }

        if (! self::isConfigured()) {
            Log::warning('Firebase push was not queued because server credentials are not configured.', [
                'user_id' => $user->id,
            ]);

            return;
        }

        try {
            SendFirebasePushNotification::dispatch($user->id, $payload)
                ->onQueue('notifications');
        } catch (Throwable $error) {
            Log::warning('Firebase push could not be queued.', [
                'user_id' => $user->id,
                'exception' => $error::class,
            ]);
        }
    }

    public static function isConfigured(): bool
    {
        $projectId = config('services.firebase.project_id');
        $credentialsPath = config('services.firebase.credentials');

        return is_string($projectId)
            && $projectId !== ''
            && is_string($credentialsPath)
            && is_file($credentialsPath);
    }

    public function sendToUser(int $userId, array $payload): void
    {
        $tokens = UserPushToken::query()->where('user_id', $userId)->get();
        if ($tokens->isEmpty()) {
            return;
        }

        $accessToken = $this->accessToken();
        $projectId = config('services.firebase.project_id');
        $endpoint = 'https://fcm.googleapis.com/v1/projects/'
            .rawurlencode($projectId).'/messages:send';

        foreach ($tokens as $deviceToken) {
            try {
                $response = Http::timeout(8)
                    ->withToken($accessToken)
                    ->acceptJson()
                    ->post($endpoint, [
                        'message' => [
                            'token' => $deviceToken->token,
                            'notification' => [
                                'title' => $payload['title'],
                                'body' => $payload['body'],
                            ],
                            'data' => $payload['data'],
                            'android' => ['priority' => 'high'],
                            'apns' => [
                                'headers' => ['apns-priority' => '10'],
                                'payload' => ['aps' => ['sound' => 'default']],
                            ],
                        ],
                    ]);
            } catch (ConnectionException $error) {
                Log::warning('Firebase push delivery failed due to a network error.', [
                    'user_id' => $userId,
                    'exception' => $error::class,
                ]);
                throw $error;
            }

            if ($response->successful()) {
                $deviceToken->forceFill(['last_used_at' => now()])->save();

                continue;
            }

            $errorCodes = collect($response->json('error.details', []))
                ->pluck('errorCode')
                ->all();
            if (in_array('UNREGISTERED', $errorCodes, true)) {
                $deviceToken->delete();
            }

            Log::warning('Firebase push delivery was rejected.', [
                'user_id' => $userId,
                'status' => $response->status(),
                'error_codes' => $errorCodes,
            ]);
            if ($response->serverError() || $response->status() === 429) {
                throw new RuntimeException(
                    "Firebase push returned HTTP {$response->status()}.",
                );
            }
        }
    }

    private function accessToken(): string
    {
        if ($this->accessToken !== null
            && $this->accessTokenExpiresAt > time() + 60) {
            return $this->accessToken;
        }

        try {
            $result = app(FirebaseMessagingAccessTokenProvider::class)->fetch();
        } catch (Throwable $error) {
            Log::error('Firebase push credentials could not be used.', [
                'exception' => $error::class,
            ]);
            throw $error;
        }

        $this->accessToken = $result['access_token'];
        $this->accessTokenExpiresAt = time() + max(
            60,
            (int) $result['expires_in'],
        );

        return $this->accessToken;
    }
}
