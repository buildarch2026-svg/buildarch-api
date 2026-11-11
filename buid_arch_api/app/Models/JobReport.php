<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class JobReport extends Model
{
    protected $fillable = [
        'user_id',
        'construction_job_id',
        'reason',
        'details',
        'status',
    ];

    public function job(): BelongsTo
    {
        return $this->belongsTo(ConstructionJob::class, 'construction_job_id');
    }

    public function reporter(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }
}
