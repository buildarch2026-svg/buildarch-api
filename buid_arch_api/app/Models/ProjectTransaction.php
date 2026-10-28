<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ProjectTransaction extends Model
{
    protected $fillable = [
        'project_id',
        'payer_user_id',
        'payee_name',
        'payee_type',
        'payee_vpa',
        'amount',
        'currency',
        'status',
        'payment_method',
        'payment_type',
        'description',
        'category',
        'provider_reference',
        'attempt_id',
        'qr_payload',
    ];

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
        ];
    }

    public function project(): BelongsTo
    {
        return $this->belongsTo(Project::class);
    }

    public function payer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'payer_user_id');
    }
}
