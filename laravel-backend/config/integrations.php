<?php

return [

    /*
    | Hosts an admin types in (mail servers, storage endpoints) must resolve to a
    | public address. Set this only for a self-hosted setup that really does live on
    | a private network. It is deliberately environment-only: an admin session must
    | never be able to turn it on.
    */
    'allow_private_hosts' => (bool) env('INTEGRATIONS_ALLOW_PRIVATE_HOSTS', false),

];
