<?php

return [
    'moderator_user_ids' => array_values(array_filter(array_map(
        'intval',
        explode(',', (string) env('JOB_PORTAL_MODERATOR_USER_IDS', '')),
    ))),
];
