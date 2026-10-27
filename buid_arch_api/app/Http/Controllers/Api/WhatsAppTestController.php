<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;

class WhatsAppTestController extends Controller
{
    public function send(Request $request): JsonResponse
    {
        abort_unless(app()->environment('local'), 404);

        $validated = $request->validate([
            'to' => ['required', 'string', 'regex:/^[1-9]\d{7,14}$/'],
        ]);

        $token = config('services.whatsapp.access_token');
        $phoneNumberId = config('services.whatsapp.phone_number_id');
        $version = config('services.whatsapp.graph_api_version');

        if (!$token || !$phoneNumberId || !$version) {
            return response()->json([
                'message' => 'WhatsApp configuration is missing.',
            ], 500);
        }

        $response = Http::withToken($token)
            ->timeout(20)
            ->post(
                "https://graph.facebook.com/{$version}/{$phoneNumberId}/messages",
                [
                    'messaging_product' => 'whatsapp',
                    'to' => $validated['to'],
                    'type' => 'template',
                    'template' => [
                        'name' => 'hello_world',
                        'language' => ['code' => 'en_US'],
                    ],
                ]
            );

        if ($response->failed()) {
            return response()->json([
                'sent' => false,
                'meta_error' => $response->json(),
            ], $response->status());
        }

        return response()->json([
            'sent' => true,
            'message_id' => $response->json('messages.0.id'),
        ]);
    }
}