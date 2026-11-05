<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

class ProjectActivityNotification extends Notification
{
    use Queueable;

    public function __construct(
        public string $event,
        public string $title,
        public string $message,
        public int $projectId,
        public string $projectName,
        public int $actorId,
        public string $actorName,
        public ?int $relatedId = null,
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
            'project_id' => $this->projectId,
            'project_name' => $this->projectName,
            'actor_id' => $this->actorId,
            'actor_name' => $this->actorName,
            'related_id' => $this->relatedId,
        ];
    }

    public function toPushPayload(array $additionalData = []): array
    {
        return [
            'title' => $this->title,
            'body' => $this->message,
            'data' => [
                'event' => $this->event,
                'project_id' => (string) $this->projectId,
                'project_name' => $this->projectName,
                'actor_id' => (string) $this->actorId,
                'actor_name' => $this->actorName,
                'related_id' => (string) ($this->relatedId ?? ''),
                ...$additionalData,
            ],
        ];
    }
}
