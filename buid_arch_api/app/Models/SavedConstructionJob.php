<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SavedConstructionJob extends Model
{
    protected $table = 'saved_construction_jobs';

    protected $fillable = [
        'construction_job_id',
        'user_id',
        'job_seeker_profile_id',
    ];

    public function job(): BelongsTo
    {
        return $this->belongsTo(ConstructionJob::class, 'construction_job_id');
    }

    public function jobSeeker(): BelongsTo
    {
        return $this->belongsTo(JobSeekerProfile::class);
    }
}
