<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ProjectMessage extends Model
{
    protected $fillable = [
        'sender_user_id',
        'body',
        'message_type',
        'attachment_path',
        'attachment_name',
        'attachment_mime_type',
        'attachment_size',
    ];

    public function conversation(): BelongsTo
    {
        return $this->belongsTo(ProjectConversation::class, 'conversation_id');
    }

    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_user_id');
    }
}
