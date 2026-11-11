<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class EmployerProfile extends Model
{
    protected $fillable = [
        'user_id',
        'company_name',
        'employer_name',
        'email',
        'phone_number',
        'company_logo_path',
        'company_description',
        'website',
        'location_name',
        'latitude',
        'longitude',
        'employer_type',
    ];

    protected function casts(): array
    {
        return [
            'latitude' => 'float',
            'longitude' => 'float',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function jobs(): HasMany
    {
        return $this->hasMany(ConstructionJob::class);
    }
}
