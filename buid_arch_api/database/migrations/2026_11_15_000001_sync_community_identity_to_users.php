<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::table('community_profiles')
            ->select(['user_id', 'display_name', 'location'])
            ->orderBy('user_id')
            ->chunk(100, function ($profiles): void {
                foreach ($profiles as $profile) {
                    $attributes = ['name' => $profile->display_name];
                    if ($profile->location !== null) {
                        $attributes['location'] = $profile->location;
                    }

                    DB::table('users')
                        ->where('id', $profile->user_id)
                        ->update($attributes);
                }
            });
    }

    public function down(): void {}
};
