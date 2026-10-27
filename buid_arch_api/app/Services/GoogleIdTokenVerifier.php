<?php

namespace App\Services;

use Google\Auth\AccessToken;
use InvalidArgumentException;
use RuntimeException;

class GoogleIdTokenVerifier
{
    private ?AccessToken $accessToken = null;

    /**
     * Return trusted Google identity claims, or null when the token is invalid.
     *
     * @return array<string, mixed>|null
     */
    public function verify(string $idToken): ?array
    {
        $clientId = config('services.google.client_id');
        if (! is_string($clientId) || trim($clientId) === '') {
            throw new GoogleIdentityVerificationUnavailable(
                'The Google web client ID is not configured.'
            );
        }

        try {
            $claims = $this->accessToken()->verify($idToken, [
                'audience' => $clientId,
            ]);
        } catch (InvalidArgumentException|RuntimeException $exception) {
            throw new GoogleIdentityVerificationUnavailable(
                'Google identity verification could not be reached.',
                previous: $exception,
            );
        }

        if (! is_array($claims)) {
            return null;
        }

        $issuer = $claims['iss'] ?? null;
        $subject = $claims['sub'] ?? null;
        $email = $claims['email'] ?? null;
        $expiresAt = $claims['exp'] ?? null;
        $audience = $claims['aud'] ?? null;

        if (! in_array($issuer, ['accounts.google.com', 'https://accounts.google.com'], true)
            || ! is_string($subject)
            || $subject === ''
            || strlen($subject) > 255
            || ! is_string($email)
            || strlen($email) > 255
            || filter_var($email, FILTER_VALIDATE_EMAIL) === false
            || ($claims['email_verified'] ?? null) !== true
            || ! is_int($expiresAt)
            || $expiresAt <= time()
            || ! is_string($audience)
            || ! hash_equals($clientId, $audience)) {
            return null;
        }

        return $claims;
    }

    protected function accessToken(): AccessToken
    {
        return $this->accessToken ??= new AccessToken;
    }
}
