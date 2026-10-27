<?php

namespace Tests\Unit;

use App\Services\GoogleIdentityVerificationUnavailable;
use App\Services\GoogleIdTokenVerifier;
use Google\Auth\AccessToken;
use GuzzleHttp\Psr7\Response;
use phpseclib3\Crypt\RSA;
use phpseclib3\Crypt\RSA\PrivateKey;
use PHPUnit\Framework\Attributes\DataProvider;
use Psr\Http\Message\RequestInterface;
use Tests\TestCase;

class GoogleIdTokenVerifierTest extends TestCase
{
    private const CLIENT_ID = 'test-google-web-client-id';

    protected function setUp(): void
    {
        parent::setUp();
        config(['services.google.client_id' => self::CLIENT_ID]);
    }

    public function test_accepts_a_valid_google_signed_id_token(): void
    {
        [$verifier, $privateKey, $jwk] = $this->makeVerifier();
        $claims = $this->validClaims();
        $token = $this->signToken($claims, $privateKey, $jwk['kid']);

        $this->assertSame($claims, $verifier->verify($token));
    }

    #[DataProvider('invalidClaims')]
    public function test_rejects_tokens_with_invalid_identity_claims(
        array $overrides,
    ): void {
        [$verifier, $privateKey, $jwk] = $this->makeVerifier();
        $claims = array_replace($this->validClaims(), $overrides);
        $token = $this->signToken($claims, $privateKey, $jwk['kid']);

        $this->assertNull($verifier->verify($token));
    }

    public static function invalidClaims(): array
    {
        return [
            'wrong audience' => [['aud' => 'another-client-id']],
            'wrong issuer' => [['iss' => 'https://attacker.example']],
            'expired' => [['exp' => 1]],
            'missing expiration' => [['exp' => null]],
            'unverified email' => [['email_verified' => false]],
            'missing subject' => [['sub' => '']],
        ];
    }

    public function test_rejects_a_token_with_an_invalid_signature(): void
    {
        [$verifier, , $jwk] = $this->makeVerifier();
        $otherKey = RSA::createKey(2048);
        $token = $this->signToken($this->validClaims(), $otherKey, $jwk['kid']);

        $this->assertNull($verifier->verify($token));
    }

    public function test_requires_a_configured_google_client_id(): void
    {
        config(['services.google.client_id' => '']);
        [$verifier] = $this->makeVerifier();

        $this->expectException(GoogleIdentityVerificationUnavailable::class);
        $verifier->verify('not-a-token');
    }

    /**
     * @return array{GoogleIdTokenVerifier, PrivateKey, array<string, string>}
     */
    private function makeVerifier(): array
    {
        $privateKey = RSA::createKey(2048);
        $publicKey = $privateKey->getPublicKey();
        $openSshKey = explode(' ', $publicKey->toString('OpenSSH'))[1];
        $decodedKey = base64_decode($openSshKey, true);
        $this->assertNotFalse($decodedKey);
        $offset = 0;
        $this->assertSame('ssh-rsa', $this->readSshValue($decodedKey, $offset));
        $exponent = $this->readSshValue($decodedKey, $offset);
        $modulus = ltrim($this->readSshValue($decodedKey, $offset), "\0");

        $jwk = [
            'kty' => 'RSA',
            'kid' => 'test-google-key',
            'alg' => 'RS256',
            'n' => $this->base64UrlEncode($modulus),
            'e' => $this->base64UrlEncode($exponent),
        ];

        $httpHandler = static function (
            RequestInterface $request,
            array $options = [],
        ) use ($jwk): Response {
            return new Response(
                200,
                ['Cache-Control' => 'max-age=3600'],
                json_encode(['keys' => [$jwk]], JSON_THROW_ON_ERROR),
            );
        };

        $accessToken = new AccessToken($httpHandler);
        $verifier = new class($accessToken) extends GoogleIdTokenVerifier
        {
            public function __construct(private readonly AccessToken $testAccessToken) {}

            protected function accessToken(): AccessToken
            {
                return $this->testAccessToken;
            }
        };

        return [$verifier, $privateKey, $jwk];
    }

    /**
     * @return array<string, mixed>
     */
    private function validClaims(): array
    {
        return [
            'iss' => 'https://accounts.google.com',
            'aud' => self::CLIENT_ID,
            'sub' => 'trusted-google-subject',
            'email' => 'trusted@example.com',
            'email_verified' => true,
            'name' => 'Trusted User',
            'exp' => time() + 3600,
        ];
    }

    private function signToken(
        array $claims,
        PrivateKey $privateKey,
        string $keyId,
    ): string {
        $header = $this->base64UrlEncode(json_encode([
            'alg' => 'RS256',
            'typ' => 'JWT',
            'kid' => $keyId,
        ], JSON_THROW_ON_ERROR));
        $payload = $this->base64UrlEncode(json_encode($claims, JSON_THROW_ON_ERROR));
        $message = $header.'.'.$payload;

        $signature = $privateKey
            ->withHash('sha256')
            ->withPadding(RSA::SIGNATURE_PKCS1)
            ->sign($message);

        return $message.'.'.$this->base64UrlEncode($signature);
    }

    private function readSshValue(string $key, int &$offset): string
    {
        $length = unpack('Nlength', substr($key, $offset, 4))['length'];
        $offset += 4;
        $value = substr($key, $offset, $length);
        $offset += $length;

        return $value;
    }

    private function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
