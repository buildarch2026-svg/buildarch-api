<?php

namespace App\Services;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use RuntimeException;

class WhatsAppOtpSender
{
    public function isConfigured(): bool
    {
        return filled(config('services.whatsapp.access_token'))
            && filled(config('services.whatsapp.phone_number_id'))
            && filled(config('services.whatsapp.otp_template'));
    }

    public function send(string $phoneNumber, string $code): void
    {
        if (! $this->isConfigured()) {
            throw new RuntimeException('WhatsApp OTP delivery is not configured.');
        }

        $version = config('services.whatsapp.graph_api_version');
        $phoneNumberId = config('services.whatsapp.phone_number_id');
        $language = config('services.whatsapp.otp_template_language');

        try {
            $response = Http::withToken(config('services.whatsapp.access_token'))
                ->acceptJson()
                ->timeout(15)
                ->post(
                    "https://graph.facebook.com/{$version}/{$phoneNumberId}/messages",
                    [
                        'messaging_product' => 'whatsapp',
                        'to' => ltrim($phoneNumber, '+'),
                        'type' => 'template',
                        'template' => [
                            'name' => config('services.whatsapp.otp_template'),
                            'language' => ['code' => $language],
                            'components' => [
                                [
                                    'type' => 'body',
                                    'parameters' => [
                                        ['type' => 'text', 'text' => $code],
                                    ],
                                ],
                                [
                                    'type' => 'button',
                                    'sub_type' => 'url',
                                    'index' => '0',
                                    'parameters' => [
                                        ['type' => 'text', 'text' => $code],
                                    ],
                                ],
                            ],
                        ],
                    ],
                );
        } catch (ConnectionException $error) {
            throw new RuntimeException(
                'WhatsApp OTP delivery failed due to a network error.',
                previous: $error,
            );
        }

        if ($response->failed()) {
            throw new RuntimeException('WhatsApp OTP delivery was rejected.');
        }
    }
}
