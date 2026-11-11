<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommunityContactRequest;
use App\Models\CommunityMemberBlock;
use App\Models\CommunityProfile;
use App\Models\User;
use App\Services\FirebasePushService;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CommunityContactController extends Controller
{
    public function __construct(private readonly FirebasePushService $pushService) {}

    public function status(Request $request, int $user): JsonResponse
    {
        $viewer = $request->user();
        $target = User::query()->with('communityProfile')->findOrFail($user);
        abort_if($viewer->id === $target->id, 422, 'You cannot request your own contact details.');
        abort_if($target->communityProfile === null, 404, 'Community member not found.');
        $blockedByMe = CommunityMemberBlock::query()
            ->where('blocker_id', $viewer->id)
            ->where('blocked_id', $target->id)
            ->exists();
        $blockedYou = CommunityMemberBlock::query()
            ->where('blocker_id', $target->id)
            ->where('blocked_id', $viewer->id)
            ->exists();
        $relationship = $this->latestRelationship($viewer->id, $target->id);

        return response()->json([
            'status' => $blockedByMe || $blockedYou
                ? 'blocked'
                : ($relationship?->status === 'accepted'
                    ? 'accepted'
                    : ($relationship?->status === 'pending'
                        ? ($relationship->requester_id === $viewer->id
                            ? 'outgoing_pending'
                            : 'incoming_pending')
                        : ($relationship?->status === 'rejected'
                            ? 'rejected'
                            : ($relationship?->status === 'revoked'
                                ? 'revoked'
                                : 'none')))),
            'request_id' => $relationship?->status === 'pending' || $relationship?->status === 'rejected'
                ? $relationship->id
                : null,
            'blocked_by_me' => $blockedByMe,
            'phone_number' => $relationship?->status === 'accepted'
                && !$blockedByMe
                && !$blockedYou
                ? $target->phone_number
                : null,
        ]);
    }

    public function send(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'receiver_id' => ['required', 'integer', 'exists:users,id'],
        ]);
        $requester = $request->user();
        $receiverId = (int) $validated['receiver_id'];
        abort_if($requester->id === $receiverId, 422, 'You cannot request your own contact details.');
        $this->requireCommunityMember($requester->id);
        $receiver = User::query()->with('communityProfile')->findOrFail($receiverId);
        abort_if($receiver->communityProfile === null, 404, 'Community member not found.');
        abort_if($this->isBlocked($requester->id, $receiverId), 403, 'Contact requests are unavailable for this member.');

        $existing = $this->latestRelationship($requester->id, $receiverId);
        if ($existing?->status === 'pending') {
            if ($existing->requester_id === $requester->id) {
                return response()->json(['request' => $this->requestResponse($existing)], 200);
            }
            return response()->json(['message' => 'This member has already requested your contact details.'], 409);
        }
        if (in_array($existing?->status, ['accepted', 'rejected'], true)) {
            return response()->json([
                'message' => $existing->status === 'accepted'
                    ? 'You are already connected.'
                    : 'This contact request was declined.',
            ], 409);
        }

        try {
            $contactRequest = CommunityContactRequest::query()->create([
                'requester_id' => $requester->id,
                'receiver_id' => $receiverId,
                'status' => 'pending',
                'active_pair_key' => self::pairKey($requester->id, $receiverId),
            ]);
        } catch (QueryException $error) {
            if (!in_array($error->getCode(), ['23000', '23505'], true)) {
                throw $error;
            }
            $contactRequest = $this->latestRelationship($requester->id, $receiverId);
            if ($contactRequest?->status === 'pending'
                && $contactRequest->requester_id === $requester->id) {
                return response()->json(['request' => $this->requestResponse($contactRequest)], 200);
            }
            return response()->json(['message' => 'A contact request already exists for these members.'], 409);
        }

        $this->notify(
            $receiver,
            'community_contact_request',
            $contactRequest,
            "{$requester->communityProfile->display_name} wants to connect with you by phone.",
        );

        return response()->json(['request' => $this->requestResponse($contactRequest)], 201);
    }

    public function index(Request $request): JsonResponse
    {
        $profile = $this->requireCommunityMember($request->user()->id);
        $rows = CommunityContactRequest::query()
            ->where(fn ($query) => $query
                ->where('requester_id', $profile->user_id)
                ->orWhere('receiver_id', $profile->user_id))
            ->with(['requester.communityProfile', 'receiver.communityProfile'])
            ->latest('id')
            ->limit(100)
            ->get()
            ->map(fn (CommunityContactRequest $item) => $this->requestResponse($item));

        return response()->json(['requests' => $rows]);
    }

    public function received(Request $request): JsonResponse
    {
        $this->requireCommunityMember($request->user()->id);
        $rows = CommunityContactRequest::query()
            ->where('receiver_id', $request->user()->id)
            ->with(['requester.communityProfile', 'receiver.communityProfile'])
            ->latest('id')
            ->limit(100)
            ->get()
            ->map(fn (CommunityContactRequest $item) => $this->requestResponse($item));

        return response()->json(['requests' => $rows]);
    }

    public function sent(Request $request): JsonResponse
    {
        $this->requireCommunityMember($request->user()->id);
        $rows = CommunityContactRequest::query()
            ->where('requester_id', $request->user()->id)
            ->with(['requester.communityProfile', 'receiver.communityProfile'])
            ->latest('id')
            ->limit(100)
            ->get()
            ->map(fn (CommunityContactRequest $item) => $this->requestResponse($item));

        return response()->json(['requests' => $rows]);
    }

    public function accept(Request $request, CommunityContactRequest $contactRequest): JsonResponse
    {
        abort_unless($contactRequest->receiver_id === $request->user()->id, 403);
        $this->requireCommunityMember($request->user()->id);
        $requester = User::query()->with('communityProfile')->findOrFail($contactRequest->requester_id);
        abort_if($this->isBlocked($contactRequest->requester_id, $contactRequest->receiver_id), 403, 'Blocked members cannot connect.');
        abort_unless($contactRequest->status === 'pending', 409, 'This request is no longer pending.');

        DB::transaction(function () use ($contactRequest): void {
            $locked = CommunityContactRequest::query()
                ->lockForUpdate()
                ->findOrFail($contactRequest->id);
            abort_unless($locked->status === 'pending', 409, 'This request is no longer pending.');
            $locked->update(['status' => 'accepted', 'accepted_at' => now()]);
        });
        $contactRequest->refresh();
        $this->notify(
            $requester,
            'community_contact_request_accepted',
            $contactRequest,
            "{$request->user()->communityProfile->display_name} accepted your contact request.",
        );

        return response()->json(['request' => $this->requestResponse($contactRequest)]);
    }

    public function reject(Request $request, CommunityContactRequest $contactRequest): JsonResponse
    {
        abort_unless($contactRequest->receiver_id === $request->user()->id, 403);
        $this->requireCommunityMember($request->user()->id);
        abort_unless($contactRequest->status === 'pending', 409, 'This request is no longer pending.');
        $requester = User::query()->with('communityProfile')->findOrFail($contactRequest->requester_id);

        DB::transaction(function () use ($contactRequest): void {
            $locked = CommunityContactRequest::query()
                ->lockForUpdate()
                ->findOrFail($contactRequest->id);
            abort_unless($locked->status === 'pending', 409, 'This request is no longer pending.');
            $locked->update(['status' => 'rejected', 'rejected_at' => now()]);
        });
        $contactRequest->refresh();
        $this->notify(
            $requester,
            'community_contact_request_rejected',
            $contactRequest,
            'Your contact request was declined.',
        );

        return response()->json(['request' => $this->requestResponse($contactRequest)]);
    }

    public function cancel(Request $request, CommunityContactRequest $contactRequest): JsonResponse
    {
        abort_unless($contactRequest->requester_id === $request->user()->id, 403);
        abort_unless($contactRequest->status === 'pending', 409, 'Only pending requests can be cancelled.');
        $contactRequest->update([
            'status' => 'cancelled',
            'active_pair_key' => null,
        ]);

        return response()->json(['message' => 'Contact request cancelled.']);
    }

    public function contacts(Request $request): JsonResponse
    {
        $this->requireCommunityMember($request->user()->id);
        $accepted = CommunityContactRequest::query()
            ->where('status', 'accepted')
            ->where(fn ($query) => $query
                ->where('requester_id', $request->user()->id)
                ->orWhere('receiver_id', $request->user()->id))
            ->with(['requester.communityProfile', 'receiver.communityProfile'])
            ->latest('accepted_at')
            ->get()
            ->filter(fn (CommunityContactRequest $item) => !$this->isBlocked(
                $item->requester_id,
                $item->receiver_id,
            ))
            ->map(function (CommunityContactRequest $item) use ($request): array {
                $other = $item->requester_id === $request->user()->id
                    ? $item->receiver
                    : $item->requester;

                return [
                    ...$this->memberResponse($other),
                    'phone_number' => $other->phone_number,
                    'request_id' => $item->id,
                ];
            })
            ->values();

        return response()->json(['contacts' => $accepted]);
    }

    public function revoke(Request $request, int $user): JsonResponse
    {
        $currentUser = $request->user();
        abort_if($currentUser->id === $user, 422, 'You cannot revoke your own contact permission.');
        $this->requireCommunityMember($currentUser->id);
        $this->requireCommunityMember($user);
        $contactRequest = CommunityContactRequest::query()
            ->where('status', 'accepted')
            ->where(fn ($query) => $query
                ->where(fn ($pair) => $pair
                    ->where('requester_id', $currentUser->id)
                    ->where('receiver_id', $user))
                ->orWhere(fn ($pair) => $pair
                    ->where('requester_id', $user)
                    ->where('receiver_id', $currentUser->id)))
            ->firstOrFail();
        $otherUser = User::query()->with('communityProfile')->findOrFail($user);

        DB::transaction(function () use ($contactRequest): void {
            $locked = CommunityContactRequest::query()
                ->lockForUpdate()
                ->findOrFail($contactRequest->id);
            abort_unless($locked->status === 'accepted', 409, 'This contact permission is no longer active.');
            $locked->update([
                'status' => 'revoked',
                'revoked_at' => now(),
                'active_pair_key' => null,
            ]);
        });
        $contactRequest->refresh();
        $this->notify(
            $otherUser,
            'community_contact_permission_revoked',
            $contactRequest,
            "{$currentUser->communityProfile->display_name} revoked phone contact permission.",
        );

        return response()->json(['message' => 'Contact permission revoked.']);
    }

    public function block(Request $request, int $user): JsonResponse
    {
        $currentUser = $request->user();
        abort_if($currentUser->id === $user, 422, 'You cannot block yourself.');
        $this->requireCommunityMember($currentUser->id);
        $this->requireCommunityMember($user);
        $accepted = $this->latestRelationship($currentUser->id, $user);
        $otherUser = User::query()->with('communityProfile')->findOrFail($user);

        DB::transaction(function () use ($currentUser, $user): void {
            CommunityMemberBlock::query()->firstOrCreate([
                'blocker_id' => $currentUser->id,
                'blocked_id' => $user,
            ]);
            CommunityContactRequest::query()
                ->where(fn ($query) => $query
                    ->where(fn ($pair) => $pair
                        ->where('requester_id', $currentUser->id)
                        ->where('receiver_id', $user))
                    ->orWhere(fn ($pair) => $pair
                        ->where('requester_id', $user)
                        ->where('receiver_id', $currentUser->id)))
                ->whereIn('status', ['pending', 'accepted'])
                ->update([
                    'status' => 'revoked',
                    'revoked_at' => now(),
                    'active_pair_key' => null,
                    'updated_at' => now(),
                ]);
        });
        if ($accepted?->status === 'accepted') {
            $accepted->refresh();
            $this->notify(
                $otherUser,
                'community_contact_permission_revoked',
                $accepted,
                "{$currentUser->communityProfile->display_name} revoked phone contact permission.",
            );
        }

        return response()->json(['blocked' => true]);
    }

    public function unblock(Request $request, int $user): JsonResponse
    {
        $this->requireCommunityMember($request->user()->id);
        abort_if($request->user()->id === $user, 422, 'You cannot unblock yourself.');
        $this->requireCommunityMember($user);
        CommunityMemberBlock::query()
            ->where('blocker_id', $request->user()->id)
            ->where('blocked_id', $user)
            ->delete();

        return response()->json(['blocked' => false]);
    }

    private function latestRelationship(int $firstUserId, int $secondUserId): ?CommunityContactRequest
    {
        return CommunityContactRequest::query()
            ->where(fn ($query) => $query
                ->where(fn ($pair) => $pair
                    ->where('requester_id', $firstUserId)
                    ->where('receiver_id', $secondUserId))
                ->orWhere(fn ($pair) => $pair
                    ->where('requester_id', $secondUserId)
                    ->where('receiver_id', $firstUserId)))
            ->latest('id')
            ->first();
    }

    private function isBlocked(int $firstUserId, int $secondUserId): bool
    {
        return CommunityMemberBlock::query()
            ->where(fn ($query) => $query
                ->where(fn ($pair) => $pair
                    ->where('blocker_id', $firstUserId)
                    ->where('blocked_id', $secondUserId))
                ->orWhere(fn ($pair) => $pair
                    ->where('blocker_id', $secondUserId)
                    ->where('blocked_id', $firstUserId)))
            ->exists();
    }

    private function requireCommunityMember(int $userId): CommunityProfile
    {
        return CommunityProfile::query()
            ->where('user_id', $userId)
            ->firstOrFail();
    }

    private function requestResponse(CommunityContactRequest $contactRequest): array
    {
        $contactRequest->loadMissing(['requester.communityProfile', 'receiver.communityProfile']);

        return [
            'id' => $contactRequest->id,
            'requester_id' => $contactRequest->requester_id,
            'receiver_id' => $contactRequest->receiver_id,
            'status' => $contactRequest->status,
            'created_at' => $contactRequest->created_at?->toIso8601String(),
            'accepted_at' => $contactRequest->accepted_at?->toIso8601String(),
            'requester' => $this->memberResponse($contactRequest->requester),
            'receiver' => $this->memberResponse($contactRequest->receiver),
        ];
    }

    private function memberResponse(User $user): array
    {
        $profile = $user->communityProfile;

        return [
            'user_id' => $user->id,
            'profile_id' => $profile?->id,
            'display_name' => $profile?->display_name ?? $user->name,
            'profession' => $profile === null
                ? 'Community member'
                : ($profile->profession === 'Other'
                    ? $profile->other_profession
                    : ($profile->profession ?? 'Community member')),
            'location' => $profile?->location,
            'profile_image_url' => $profile?->profile_image_path === null
                ? null
                : url("/api/community/media/profiles/{$profile->id}"),
        ];
    }

    private function notify(
        User $user,
        string $type,
        CommunityContactRequest $contactRequest,
        string $body,
    ): void {
        $this->pushService->queue($user, [
            'title' => 'Community phone contact',
            'body' => $body,
            'data' => [
                'notification_type' => $type,
                'request_id' => (string) $contactRequest->id,
                'requester_id' => (string) $contactRequest->requester_id,
                'receiver_id' => (string) $contactRequest->receiver_id,
            ],
        ]);
    }

    private static function pairKey(int $firstUserId, int $secondUserId): string
    {
        return min($firstUserId, $secondUserId).':'.max($firstUserId, $secondUserId);
    }
}
