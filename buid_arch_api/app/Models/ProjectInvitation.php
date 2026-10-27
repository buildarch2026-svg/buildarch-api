<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ProjectInvitation extends Model
{
    protected $fillable = [
        'project_id',
        'invited_by_user_id',
        'role',
        'token_hash',
        'token_encrypted',
        'status',
        'expires_at',
        'accepted_by_user_id',
        'accepted_at',
        'declined_by_user_id',
        'declined_at',
        'revoked_at',
    ];

    protected function casts(): array
    {
        return [
            'expires_at' => 'datetime',
            'accepted_at' => 'datetime',
            'declined_at' => 'datetime',
            'revoked_at' => 'datetime',
        ];
    }

    public function project(): BelongsTo
    {
        return $this->belongsTo(Project::class);
    }

    public function invitedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'invited_by_user_id');
    }

    public function acceptedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'accepted_by_user_id');
    }

    public function declinedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'declined_by_user_id');
    }

    public function refreshExpirationStatus(): void
    {
        if ($this->status === 'pending' && $this->expires_at->isPast()) {
            $this->status = 'expired';
            $this->save();
        }
    }
}
