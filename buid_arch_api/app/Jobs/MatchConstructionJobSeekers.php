<?php

namespace App\Jobs;

use App\Models\CommunityProfile;
use App\Models\ConstructionJob;
use App\Services\FirebasePushService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\DB;

class MatchConstructionJobSeekers implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;

    public array $backoff = [10, 30, 60];

    public function __construct(public int $jobId) {}

    public function handle(FirebasePushService $pushService): void
    {
        $job = ConstructionJob::query()
            ->with(['category:id,slug,name', 'poster', 'employer'])
            ->find($this->jobId);
        if ($job === null
            || $job->status !== 'published'
            || ($job->application_deadline !== null && $job->application_deadline->isPast())
            || $job->latitude === null
            || $job->longitude === null
            || $job->category === null) {
            return;
        }
        $posterUserId = $job->employer_id ?? $job->employer?->user_id;

        $profiles = CommunityProfile::query()
            ->where('job_notifications_enabled', true)
            ->with('user')
            ->get();

        foreach ($profiles as $profile) {
            $latitude = $profile->preferred_latitude ?? $profile->latitude;
            $longitude = $profile->preferred_longitude ?? $profile->longitude;
            if ($profile->user_id === $posterUserId
                || $latitude === null
                || $longitude === null
                || ! in_array((int) $job->job_portal_category_id, array_map(
                    'intval',
                    $profile->preferred_categories ?? [],
                ), true)
            ) {
                continue;
            }

            $distance = self::distanceInKilometers(
                (float) $latitude,
                (float) $longitude,
                (float) $job->latitude,
                (float) $job->longitude,
            );
            if ($distance > $profile->preferred_radius_km) {
                continue;
            }

            $sentAt = now();
            $inserted = DB::table('job_notifications')->insertOrIgnore([
                'user_id' => $profile->user_id,
                'construction_job_id' => $job->id,
                'notification_type' => 'nearby_construction_job',
                'sent_at' => $sentAt,
                'created_at' => $sentAt,
                'updated_at' => $sentAt,
            ]);
            if ($inserted === 0) {
                continue;
            }

            $pushService->queue($profile->user, [
                'title' => 'New Construction Job Near You!',
                'body' => "New {$job->category->name} Job Available – {$job->location_name} "
                    .number_format($distance, 1).' km away. '
                    .($job->min_salary !== null
                        ? "{$job->min_salary} {$job->salary_type}. "
                        : '')
                    ."{$job->vacancies} vacancies.",
                'data' => [
                    'job_id' => (string) $job->id,
                    'job_title' => $job->title,
                    'job_category' => $job->category->name,
                    'job_location' => $job->location_name,
                    'notification_type' => 'nearby_construction_job',
                ],
            ]);
        }
    }

    private static function distanceInKilometers(
        float $latitude,
        float $longitude,
        float $targetLatitude,
        float $targetLongitude,
    ): float {
        $latitudeDelta = deg2rad($targetLatitude - $latitude);
        $longitudeDelta = deg2rad($targetLongitude - $longitude);
        $a = sin($latitudeDelta / 2) ** 2
            + cos(deg2rad($latitude))
            * cos(deg2rad($targetLatitude))
            * sin($longitudeDelta / 2) ** 2;

        return 6371 * 2 * asin(sqrt(min(1, $a)));
    }
}
