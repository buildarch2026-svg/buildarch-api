<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class CommunityLike extends Model
{
    protected $fillable = ['community_post_id', 'community_profile_id'];

    public function post(): BelongsTo
    {
        return $this->belongsTo(CommunityPost::class, 'community_post_id');
    }

    public function profile(): BelongsTo
    {
        return $this->belongsTo(CommunityProfile::class, 'community_profile_id');
    }
}
