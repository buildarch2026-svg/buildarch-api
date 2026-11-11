<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class JobPortalNotification extends Notification
{
    use Queueable;

    public function __construct(
        public string $event,
        public string $title,
        public string $message,
        public int $jobId,
        public string $jobTitle,
        public ?int $applicationId = null,
    ) {}

    public function via(object $notifiable): array
    {
        return ['database'];
    }

    public function toArray(object $notifiable): array
    {
        return [
            'event' => $this->event,
            'title' => $this->title,
            'message' => $this->message,
            'job_id' => $this->jobId,
            'job_title' => $this->jobTitle,
            'related_id' => $this->applicationId,
        ];
    }

    public function toPushPayload(): array
    {
        return [
            'title' => $this->title,
            'body' => $this->message,
            'data' => [
                'event' => $this->event,
                'job_id' => (string) $this->jobId,
                'job_title' => $this->jobTitle,
                'related_id' => (string) ($this->applicationId ?? ''),
            ],
        ];
    }
}
