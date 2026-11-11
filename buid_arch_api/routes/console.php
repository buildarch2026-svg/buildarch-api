<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Artisan::command('construction-jobs:expire', function () {
    $expired = DB::table('construction_jobs')
        ->where('status', 'published')
        ->whereNotNull('application_deadline')
        ->where('application_deadline', '<', now())
        ->update(['status' => 'expired', 'updated_at' => now()]);

    $this->info("Expired {$expired} construction job(s).");
})->purpose('Expire construction job postings past their deadline');

Schedule::command('construction-jobs:expire')->daily();
