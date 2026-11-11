<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class ConstructionJob extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'employer_id',
        'employer_profile_id',
        'job_portal_category_id',
        'title',
        'description',
        'employment_type',
        'other_category_description',
        'contact_preference',
        'additional_instructions',
        'experience_required',
        'min_salary',
        'max_salary',
        'salary_type',
        'qualifications',
        'skills',
        'vacancies',
        'location_name',
        'latitude',
        'longitude',
        'application_deadline',
        'work_start_date',
        'contact_email',
        'contact_phone',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'qualifications' => 'array',
            'skills' => 'array',
            'min_salary' => 'float',
            'max_salary' => 'float',
            'latitude' => 'float',
            'longitude' => 'float',
            'vacancies' => 'integer',
            'application_deadline' => 'datetime',
            'work_start_date' => 'date',
        ];
    }

    public function employer(): BelongsTo
    {
        return $this->belongsTo(EmployerProfile::class, 'employer_profile_id');
    }

    public function poster(): BelongsTo
    {
        return $this->belongsTo(User::class, 'employer_id');
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(JobPortalCategory::class, 'job_portal_category_id');
    }

    public function applications(): HasMany
    {
        return $this->hasMany(JobApplication::class, 'construction_job_id');
    }

    public function savedBy(): HasMany
    {
        return $this->hasMany(SavedConstructionJob::class, 'construction_job_id');
    }
}
