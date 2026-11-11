<?php

return [
    'moderator_user_ids' => array_values(array_filter(array_map(
        'intval',
        explode(',', (string) env('COMMUNITY_MODERATOR_USER_IDS', '')),
    ))),
];
