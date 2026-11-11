<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class CommunityProfile extends Model
{
    protected $fillable = [
        'user_id',
        'display_name',
        'profession',
        'other_profession',
        'location',
        'bio',
        'profile_image_path',
        'guidelines_accepted_at',
        'is_phone_visible',
        'latitude',
        'longitude',
        'skills',
        'experience_years',
        'preferred_location',
        'preferred_latitude',
        'preferred_longitude',
        'preferred_categories',
        'preferred_radius_km',
        'job_notifications_enabled',
        'trade',
    ];

    protected function casts(): array
    {
        return [
            'guidelines_accepted_at' => 'datetime',
            'is_phone_visible' => 'boolean',
            'latitude' => 'float',
            'longitude' => 'float',
            'skills' => 'array',
            'experience_years' => 'integer',
            'preferred_latitude' => 'float',
            'preferred_longitude' => 'float',
            'preferred_categories' => 'array',
            'preferred_radius_km' => 'integer',
            'job_notifications_enabled' => 'boolean',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function posts(): HasMany
    {
        return $this->hasMany(CommunityPost::class);
    }

    public function comments(): HasMany
    {
        return $this->hasMany(CommunityComment::class);
    }

    public function likes(): HasMany
    {
        return $this->hasMany(CommunityLike::class);
    }

    public function reports(): HasMany
    {
        return $this->hasMany(CommunityReport::class, 'reporter_profile_id');
    }
}
