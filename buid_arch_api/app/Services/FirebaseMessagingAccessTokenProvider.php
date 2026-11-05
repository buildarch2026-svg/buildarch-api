<?php

namespace App\Services;

use Google\Auth\Credentials\ServiceAccountCredentials;
use RuntimeException;

class FirebaseMessagingAccessTokenProvider
{
    public function fetch(): array
    {
        $credentialsPath = config('services.firebase.credentials');
        if (! is_string($credentialsPath) || ! is_file($credentialsPath)) {
            throw new RuntimeException('Firebase service-account credentials are unavailable.');
        }

        $credentials = new ServiceAccountCredentials(
            ['https://www.googleapis.com/auth/firebase.messaging'],
            $credentialsPath,
        );
        $token = $credentials->fetchAuthToken();
        if (! is_string($token['access_token'] ?? null)
            || ! is_numeric($token['expires_in'] ?? null)) {
            throw new RuntimeException('Google did not return an FCM access token.');
        }

        return $token;
    }
}
