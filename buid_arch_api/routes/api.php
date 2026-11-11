<?php

use App\Http\Controllers\Api\AccountController;
use App\Http\Controllers\Api\Auth\OtpController;
use App\Http\Controllers\Api\CommunityContactController;
use App\Http\Controllers\Api\CommunityController;
use App\Http\Controllers\Api\JobPortalController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\ProjectChatController;
use App\Http\Controllers\Api\ProjectController;
use App\Http\Controllers\Api\ProjectDocumentController;
use App\Http\Controllers\Api\ProjectGroupChatController;
use App\Http\Controllers\Api\ProjectInvitationController;
use App\Http\Controllers\Api\ProjectMemberController;
use App\Http\Controllers\Api\ProjectMessageController;
use App\Http\Controllers\Api\ProjectTransactionController;
use App\Http\Controllers\Api\PushTokenController;
use App\Http\Controllers\Api\UserProfileController;
use App\Http\Controllers\Api\WhatsAppTestController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Broadcast;
use Illuminate\Support\Facades\Route;

Broadcast::routes(['middleware' => ['auth:sanctum']]);

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');
Route::middleware('auth:sanctum')->group(function () {
    Route::get('/me', [AccountController::class, 'me']);
    Route::get('/account/access', [AccountController::class, 'access']);
    Route::post('/account/upgrade', [AccountController::class, 'upgrade'])
        ->middleware('throttle:10,1');
});

Route::patch('/user/profile', [UserProfileController::class, 'update'])
    ->middleware('auth:sanctum');

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/jobs/categories', [JobPortalController::class, 'categories'])
        ->middleware('throttle:60,1');
    Route::get('/jobs/dashboard', [JobPortalController::class, 'dashboard'])
        ->middleware('throttle:60,1');
    Route::get('/jobs/employer-profiles/{profile}/logo', [JobPortalController::class, 'companyLogo'])
        ->whereNumber('profile')->name('jobs.employer-logo');
    Route::get('/jobs/job-seeker-profiles/{profile}/image', [JobPortalController::class, 'seekerImage'])
        ->whereNumber('profile')->name('jobs.seeker-image');
    Route::get('/jobs/my-postings', [JobPortalController::class, 'myJobs']);
    Route::get('/jobs/saved', [JobPortalController::class, 'savedJobs']);
    Route::get('/jobs/applications', [JobPortalController::class, 'myApplications']);
    Route::get('/jobs/notifications', [JobPortalController::class, 'jobNotifications']);
    Route::post('/jobs/notifications/{notification}/read', [JobPortalController::class, 'markJobNotificationRead'])
        ->whereNumber('notification');
    Route::get('/jobs/moderation/reports', [JobPortalController::class, 'moderationReports'])
        ->middleware('throttle:30,1');
    Route::put('/jobs/moderation/reports/{report}', [JobPortalController::class, 'updateJobReport'])
        ->whereNumber('report')->middleware('throttle:30,1');
    Route::get('/jobs/applications/{application}/resume', [JobPortalController::class, 'downloadResume'])
        ->whereNumber('application')->name('jobs.application-resume');
    Route::patch('/jobs/applications/{application}', [JobPortalController::class, 'updateApplication'])
        ->whereNumber('application')->middleware('throttle:30,1');
    Route::post('/jobs/applications/{application}/withdraw', [JobPortalController::class, 'withdrawApplication'])
        ->whereNumber('application')->middleware('throttle:20,1');
    Route::get('/jobs/{job}', [JobPortalController::class, 'showJob'])
        ->whereNumber('job')->middleware('throttle:60,1');
    Route::get('/jobs', [JobPortalController::class, 'jobs'])
        ->middleware('throttle:60,1');
    Route::post('/jobs', [JobPortalController::class, 'createJob'])
        ->middleware('throttle:20,1');
    Route::delete('/jobs/{job}', [JobPortalController::class, 'deleteJob'])
        ->whereNumber('job')->middleware('throttle:20,1');
    Route::patch('/jobs/{job}', [JobPortalController::class, 'updateJob'])
        ->whereNumber('job')->middleware('throttle:20,1');
    Route::put('/jobs/{job}/status', [JobPortalController::class, 'updateJobStatus'])
        ->whereNumber('job')->middleware('throttle:20,1');
    Route::put('/jobs/{job}/saved', [JobPortalController::class, 'saveJob'])
        ->whereNumber('job')->middleware('throttle:30,1');
    Route::delete('/jobs/{job}/saved', [JobPortalController::class, 'unsaveJob'])
        ->whereNumber('job')->middleware('throttle:30,1');
    Route::post('/jobs/{job}/applications', [JobPortalController::class, 'apply'])
        ->whereNumber('job')->middleware('throttle:10,1');
    Route::get('/jobs/{job}/applications', [JobPortalController::class, 'employerApplications'])
        ->whereNumber('job');
    Route::post('/jobs/{job}/reports', [JobPortalController::class, 'reportJob'])
        ->whereNumber('job')->middleware('throttle:10,1');

    Route::get('/community/categories', [CommunityController::class, 'categories'])
        ->middleware('throttle:60,1');
    Route::get('/community/preview', [CommunityController::class, 'preview'])
        ->middleware('throttle:60,1');
    Route::get('/community/profile', [CommunityController::class, 'profile'])
        ->middleware('throttle:60,1');
    Route::post('/community/profile', [CommunityController::class, 'register'])
        ->middleware('throttle:10,1');
    Route::post('/community/register', [CommunityController::class, 'register'])
        ->middleware('throttle:10,1');
    Route::patch('/community/profile', [CommunityController::class, 'updateProfile'])
        ->middleware('throttle:20,1');
    Route::post('/community/profile/image', [CommunityController::class, 'updateProfileImage'])
        ->middleware('throttle:10,1');
    Route::delete('/community/profile/image', [CommunityController::class, 'removeProfileImage'])
        ->middleware('throttle:10,1');
    Route::get('/community/profiles/{profile}', [CommunityController::class, 'showProfile'])
        ->whereNumber('profile')->middleware('throttle:60,1');
    Route::post('/community/contact-requests', [CommunityContactController::class, 'send'])
        ->middleware('throttle:10,1');
    Route::get('/community/contact-requests', [CommunityContactController::class, 'index']);
    Route::get('/community/contact-requests/received', [CommunityContactController::class, 'received']);
    Route::get('/community/contact-requests/sent', [CommunityContactController::class, 'sent']);
    Route::put('/community/contact-requests/{contactRequest}/accept', [CommunityContactController::class, 'accept'])
        ->whereNumber('contactRequest')->middleware('throttle:20,1');
    Route::put('/community/contact-requests/{contactRequest}/reject', [CommunityContactController::class, 'reject'])
        ->whereNumber('contactRequest')->middleware('throttle:20,1');
    Route::delete('/community/contact-requests/{contactRequest}/cancel', [CommunityContactController::class, 'cancel'])
        ->whereNumber('contactRequest')->middleware('throttle:20,1');
    Route::get('/community/contacts', [CommunityContactController::class, 'contacts']);
    Route::delete('/community/contacts/{user}', [CommunityContactController::class, 'revoke'])
        ->whereNumber('user')->middleware('throttle:20,1');
    Route::get('/community/members/{user}/contact-status', [CommunityContactController::class, 'status'])
        ->whereNumber('user')->middleware('throttle:60,1');
    Route::post('/community/blocks/{user}', [CommunityContactController::class, 'block'])
        ->whereNumber('user')->middleware('throttle:20,1');
    Route::delete('/community/blocks/{user}', [CommunityContactController::class, 'unblock'])
        ->whereNumber('user')->middleware('throttle:20,1');
    Route::get('/community/profiles/{profile}/posts', [CommunityController::class, 'profilePosts'])
        ->whereNumber('profile')->middleware('throttle:60,1');
    Route::get('/community/media/profiles/{profile}', [CommunityController::class, 'profileImage'])
        ->whereNumber('profile')->middleware('throttle:120,1');
    Route::get('/community/media/posts/{post}', [CommunityController::class, 'postImage'])
        ->whereNumber('post')->middleware('throttle:120,1');
    Route::get('/community/media/posts/{post}/{image}', [CommunityController::class, 'postImageAtIndex'])
        ->whereNumber('post')->whereNumber('image')->middleware('throttle:120,1');
    Route::get('/community/feed', [CommunityController::class, 'feed'])
        ->middleware('throttle:60,1');
    Route::post('/community/posts', [CommunityController::class, 'createPost'])
        ->middleware('throttle:20,1');
    Route::post('/community/posts/{post}', [CommunityController::class, 'updatePost'])
        ->whereNumber('post')->middleware('throttle:20,1');
    Route::patch('/community/posts/{post}', [CommunityController::class, 'updatePost'])
        ->whereNumber('post')->middleware('throttle:20,1');
    Route::delete('/community/posts/{post}', [CommunityController::class, 'deletePost'])
        ->whereNumber('post')->middleware('throttle:20,1');
    Route::put('/community/posts/{post}/like', [CommunityController::class, 'setLike'])
        ->whereNumber('post')->middleware('throttle:60,1');
    Route::get('/community/posts/{post}/comments', [CommunityController::class, 'comments'])
        ->whereNumber('post')->middleware('throttle:60,1');
    Route::post('/community/posts/{post}/comments', [CommunityController::class, 'createComment'])
        ->whereNumber('post')->middleware('throttle:30,1');
    Route::delete(
        '/community/posts/{post}/comments/{comment}',
        [CommunityController::class, 'deleteComment'],
    )->whereNumber('post')->whereNumber('comment')->middleware('throttle:20,1');
    Route::post('/community/reports', [CommunityController::class, 'report'])
        ->middleware('throttle:10,1');
    Route::get('/community/moderation/reports', [CommunityController::class, 'reports'])
        ->middleware('throttle:30,1');
    Route::patch(
        '/community/moderation/reports/{report}',
        [CommunityController::class, 'reviewReport'],
    )->whereNumber('report')->middleware('throttle:30,1');

    Route::post('/push-tokens', [PushTokenController::class, 'store'])
        ->middleware('throttle:30,1');
    Route::delete('/push-tokens', [PushTokenController::class, 'destroy'])
        ->middleware('throttle:30,1');
    Route::post('/auth/logout', function (Request $request) {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'message' => 'Signed out successfully.',
        ]);
    });
    Route::get('/chats', [ProjectChatController::class, 'index'])
        ->middleware('main-app')
        ->middleware('throttle:60,1');
    Route::get('/notifications', [NotificationController::class, 'index'])
        ->middleware('throttle:60,1');
    Route::post('/notifications/{notificationId}/read', [NotificationController::class, 'markRead'])
        ->middleware('throttle:60,1');
    Route::middleware('main-app')->group(function () {
        Route::get('/projects', [ProjectController::class, 'index']);
        Route::post('/projects', [ProjectController::class, 'store']);
        Route::patch('/projects/{project}', [ProjectController::class, 'update'])
            ->middleware('project.active');
        Route::post('/projects/{project}/archive', [ProjectController::class, 'archive']);
        Route::delete('/projects/{project}', [ProjectController::class, 'delete']);
        Route::post('/projects/{project}/restore', [ProjectController::class, 'restore'])
            ->withTrashed();
        Route::delete(
            '/projects/{project}/members/{memberUserId}',
            [ProjectMemberController::class, 'destroy'],
        )->whereNumber('memberUserId')->middleware('project.active');

        Route::middleware('project.active')->group(function () {
            Route::post(
                '/projects/{project}/chat/forward',
                [ProjectChatController::class, 'forward'],
            )->middleware('throttle:30,1');
            Route::post('/projects/{project}/photo', [ProjectController::class, 'updatePhoto'])
                ->middleware('throttle:10,1');
            Route::get('/projects/{project}/group-chat', [ProjectGroupChatController::class, 'index'])
                ->middleware('throttle:60,1');
            Route::get('/projects/{project}/group-chat/files', [ProjectGroupChatController::class, 'files'])
                ->middleware('throttle:30,1');
            Route::get('/projects/{project}/chat/files', [ProjectMessageController::class, 'files'])
                ->middleware('throttle:30,1');
            Route::post(
                '/projects/{project}/group-chat/messages',
                [ProjectGroupChatController::class, 'storeText'],
            )->middleware('throttle:30,1');
            Route::patch(
                '/projects/{project}/group-chat/messages/{message}',
                [ProjectGroupChatController::class, 'updateMessage'],
            )->whereNumber('message')->middleware('throttle:30,1');
            Route::delete(
                '/projects/{project}/group-chat/messages/{message}',
                [ProjectGroupChatController::class, 'deleteMessage'],
            )->whereNumber('message')->middleware('throttle:30,1');
            Route::post(
                '/projects/{project}/group-chat/read',
                [ProjectGroupChatController::class, 'markRead'],
            )->middleware('throttle:60,1');
            Route::post(
                '/projects/{project}/group-chat/location',
                [ProjectGroupChatController::class, 'storeLocation'],
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
            Route::patch(
                '/projects/{project}/members/{memberUserId}/messages/{message}',
                [ProjectMessageController::class, 'updateMessage'],
            )->whereNumber('memberUserId')->whereNumber('message')->middleware('throttle:30,1');
            Route::delete(
                '/projects/{project}/members/{memberUserId}/messages/{message}',
                [ProjectMessageController::class, 'deleteMessage'],
            )->whereNumber('memberUserId')->whereNumber('message')->middleware('throttle:30,1');
            Route::post(
                '/projects/{project}/members/{memberUserId}/messages/read',
                [ProjectMessageController::class, 'markRead'],
            )->whereNumber('memberUserId')->middleware('throttle:60,1');
            Route::post(
                '/projects/{project}/members/{memberUserId}/messages/location',
                [ProjectMessageController::class, 'storeLocation'],
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
            Route::get('/projects/{project}/transactions', [ProjectTransactionController::class, 'index'])
                ->middleware('throttle:30,1');
            Route::post('/projects/{project}/transactions', [ProjectTransactionController::class, 'store'])
                ->middleware('throttle:30,1');
            Route::patch(
                '/projects/{project}/transactions/{transaction}',
                [ProjectTransactionController::class, 'updateStatus'],
            )->whereNumber('transaction')->middleware('throttle:30,1');
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
        });
    });
    Route::get('/invitations/{token}', [ProjectInvitationController::class, 'show'])
        ->middleware(['main-app', 'throttle:30,1']);
    Route::post('/invitations/{token}/accept', [ProjectInvitationController::class, 'accept'])
        ->middleware(['main-app', 'throttle:10,1']);
    Route::post('/invitations/{token}/decline', [ProjectInvitationController::class, 'decline'])
        ->middleware(['main-app', 'throttle:10,1']);
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
