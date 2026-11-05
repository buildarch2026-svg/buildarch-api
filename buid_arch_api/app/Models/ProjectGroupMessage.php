<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ProjectGroupMessage extends Model
{
    protected $fillable = [
        'sender_user_id',
        'body',
        'message_type',
        'attachment_path',
        'attachment_name',
        'attachment_mime_type',
        'attachment_size',
        'reply_to_message_id',
        'forwarded_from_name',
        'location_latitude',
        'location_longitude',
        'location_address',
    ];

    public function conversation(): BelongsTo
    {
        return $this->belongsTo(ProjectGroupConversation::class, 'conversation_id');
    }

    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_user_id');
    }

    public function replyTo(): BelongsTo
    {
        return $this->belongsTo(self::class, 'reply_to_message_id');
    }

    protected function casts(): array
    {
        return [
            'edited_at' => 'datetime',
            'deleted_at' => 'datetime',
            'location_latitude' => 'float',
            'location_longitude' => 'float',
        ];
    }
}
