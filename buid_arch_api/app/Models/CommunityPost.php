<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class CommunityPost extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'community_profile_id',
        'community_category_id',
        'content',
        'image_path',
        'image_paths',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'image_paths' => 'array',
        ];
    }

    public function profile(): BelongsTo
    {
        return $this->belongsTo(CommunityProfile::class, 'community_profile_id');
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(CommunityCategory::class, 'community_category_id');
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
        return $this->hasMany(CommunityReport::class, 'target_id')
            ->where('target_type', 'post');
    }
}
