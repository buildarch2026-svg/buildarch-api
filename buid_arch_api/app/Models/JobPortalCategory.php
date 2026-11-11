<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class JobPortalCategory extends Model
{
    protected $fillable = ['slug', 'name', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function jobs(): HasMany
    {
        return $this->hasMany(ConstructionJob::class);
    }
}
