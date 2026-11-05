<?php

namespace App\Events;

use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class ProjectChatMessageChanged implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(
        public int $projectId,
        public string $conversationType,
        public int $conversationId,
        public ?int $memberUserId,
        public array $message,
        public string $change = 'created',
    ) {}

    public function broadcastOn(): array
    {
        $name = $this->conversationType === 'group'
            ? "project-chat.group.{$this->projectId}"
            : "project-chat.direct.{$this->projectId}.{$this->memberUserId}";

        return [new PrivateChannel($name)];
    }

    public function broadcastAs(): string
    {
        return 'chat.message.changed';
    }

    public function broadcastWith(): array
    {
        return [
            'change' => $this->change,
            'message' => $this->message,
        ];
    }
}
