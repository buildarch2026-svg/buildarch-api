<?php

use App\Http\Controllers\Api\Auth\OtpController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\ProjectController;
use App\Http\Controllers\Api\ProjectDocumentController;
use App\Http\Controllers\Api\ProjectGroupChatController;
use App\Http\Controllers\Api\ProjectInvitationController;
use App\Http\Controllers\Api\ProjectMemberController;
use App\Http\Controllers\Api\ProjectMessageController;
use App\Http\Controllers\Api\UserProfileController;
use App\Http\Controllers\Api\WhatsAppTestController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');

Route::patch('/user/profile', [UserProfileController::class, 'update'])
    ->middleware('auth:sanctum');

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/auth/logout', function (Request $request) {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'message' => 'Signed out successfully.',
        ]);
    });
    Route::get('/notifications', [NotificationController::class, 'index'])
        ->middleware('throttle:60,1');
    Route::post('/notifications/{notificationId}/read', [NotificationController::class, 'markRead'])
        ->middleware('throttle:60,1');
    Route::get('/projects', [ProjectController::class, 'index']);
    Route::post('/projects', [ProjectController::class, 'store']);
    Route::post('/projects/{project}/photo', [ProjectController::class, 'updatePhoto'])
        ->middleware('throttle:10,1');
    Route::get('/projects/{project}/group-chat', [ProjectGroupChatController::class, 'index'])
        ->middleware('throttle:60,1');
    Route::get('/projects/{project}/group-chat/files', [ProjectGroupChatController::class, 'files'])
        ->middleware('throttle:30,1');
    Route::post(
        '/projects/{project}/group-chat/messages',
        [ProjectGroupChatController::class, 'storeText'],
    )->middleware('throttle:30,1');
    Route::post(
        '/projects/{project}/group-chat/voice',
        [ProjectGroupChatController::class, 'storeAttachment'],
    )->middleware('throttle:10,1');
    Route::get(
        '/projects/{project}/group-chat/voice/{message}',
        [ProjectGroupChatController::class, 'downloadAttachment'],
    )->whereNumber('message')->middleware('throttle:30,1');
    Route::post(
        '/projects/{project}/group-chat/attachments',
        [ProjectGroupChatController::class, 'storeAttachment'],
    )->middleware('throttle:10,1');
    Route::get(
        '/projects/{project}/group-chat/attachments/{message}',
        [ProjectGroupChatController::class, 'downloadAttachment'],
    )->middleware('throttle:30,1');
    Route::get('/projects/{project}/invitations', [ProjectInvitationController::class, 'index'])
        ->middleware('throttle:30,1');
    Route::get('/projects/{project}/members', [ProjectMemberController::class, 'index'])
        ->middleware('throttle:30,1');
    Route::get(
        '/projects/{project}/members/{memberUserId}/messages',
        [ProjectMessageController::class, 'index'],
    )->whereNumber('memberUserId')->middleware('throttle:60,1');
    Route::post(
        '/projects/{project}/members/{memberUserId}/messages',
        [ProjectMessageController::class, 'store'],
    )->whereNumber('memberUserId')->middleware('throttle:30,1');
    Route::post(
        '/projects/{project}/members/{memberUserId}/messages/attachments',
        [ProjectMessageController::class, 'storeAttachment'],
    )->whereNumber('memberUserId')->middleware('throttle:10,1');
    Route::get(
        '/projects/{project}/members/{memberUserId}/messages/{message}/attachment',
        [ProjectMessageController::class, 'downloadAttachment'],
    )->whereNumber('memberUserId')->whereNumber('message')->middleware('throttle:30,1');
    Route::get('/projects/{project}/documents', [ProjectDocumentController::class, 'index'])
        ->middleware('throttle:30,1');
    Route::post('/projects/{project}/documents', [ProjectDocumentController::class, 'store'])
        ->middleware('throttle:10,1');
    Route::get(
        '/projects/{project}/documents/{document}',
        [ProjectDocumentController::class, 'download'],
    )->middleware('throttle:30,1');
    Route::post('/projects/{project}/invitations', [ProjectInvitationController::class, 'store'])
        ->middleware('throttle:10,1');
    Route::post(
        '/projects/{project}/invitations/{invitation}/revoke',
        [ProjectInvitationController::class, 'revoke'],
    )->middleware('throttle:30,1');
    Route::get('/invitations/{token}', [ProjectInvitationController::class, 'show'])
        ->middleware('throttle:30,1');
    Route::post('/invitations/{token}/accept', [ProjectInvitationController::class, 'accept'])
        ->middleware('throttle:10,1');
    Route::post('/invitations/{token}/decline', [ProjectInvitationController::class, 'decline'])
        ->middleware('throttle:10,1');
});

Route::post('/user/profile/phone/verify', [OtpController::class, 'verifyProfilePhone'])
    ->middleware(['auth:sanctum', 'throttle:10,1']);

Route::post('/user/profile/phone/request', [OtpController::class, 'sendProfilePhoneOtp'])
    ->middleware(['auth:sanctum', 'throttle:3,10']);

Route::post('/auth/otp/request', [OtpController::class, 'send'])
    ->middleware('throttle:3,10');

Route::post('/auth/otp/verify', [OtpController::class, 'verify'])
    ->middleware('throttle:10,1');

Route::post('/auth/google', [OtpController::class, 'google'])
    ->middleware('throttle:10,1');

Route::post('/whatsapp/test-message', [WhatsAppTestController::class, 'send'])
    ->middleware('throttle:3,1');
