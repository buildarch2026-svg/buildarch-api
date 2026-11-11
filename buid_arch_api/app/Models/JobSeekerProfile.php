<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class JobSeekerProfile extends Model
{
    protected $fillable = [
        'user_id',
        'full_name',
        'email',
        'phone_number',
        'profile_image_path',
        'current_location',
        'current_latitude',
        'current_longitude',
        'preferred_location',
        'preferred_latitude',
        'preferred_longitude',
        'preferred_categories',
        'preferred_employment_types',
        'preferred_radius_km',
        'expected_salary',
        'available_from',
        'notifications_enabled',
        'profession',
        'skills',
        'experience_years',
        'education',
        'resume_path',
        'resume_name',
        'bio',
    ];

    protected function casts(): array
    {
        return [
            'skills' => 'array',
            'experience_years' => 'integer',
            'current_latitude' => 'float',
            'current_longitude' => 'float',
            'preferred_latitude' => 'float',
            'preferred_longitude' => 'float',
            'preferred_categories' => 'array',
            'preferred_employment_types' => 'array',
            'preferred_radius_km' => 'integer',
            'expected_salary' => 'float',
            'available_from' => 'date',
            'notifications_enabled' => 'boolean',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function applications(): HasMany
    {
        return $this->hasMany(JobApplication::class);
    }

    public function savedJobs(): HasMany
    {
        return $this->hasMany(SavedConstructionJob::class);
    }
}
