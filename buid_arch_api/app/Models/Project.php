<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class Project extends Model
{
    protected $fillable = [
        'name',
        'location',
        'latitude',
        'longitude',
        'type',
        'image_path',
    ];

    protected function casts(): array
    {
        return [
            'progress' => 'float',
            'latitude' => 'float',
            'longitude' => 'float',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function members(): HasMany
    {
        return $this->hasMany(ProjectMember::class);
    }

    public function invitations(): HasMany
    {
        return $this->hasMany(ProjectInvitation::class);
    }

    public function documents(): HasMany
    {
        return $this->hasMany(ProjectDocument::class);
    }

    public function directConversations(): HasMany
    {
        return $this->hasMany(ProjectConversation::class);
    }

    public function groupConversation(): HasOne
    {
        return $this->hasOne(ProjectGroupConversation::class);
    }
}
