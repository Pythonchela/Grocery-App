<?php

namespace App\Integrations\Testers;

/**
 * Checks whether a set of credentials actually works, by calling the provider.
 *
 * Rules every tester follows, because this endpoint is reachable by an admin
 * session and therefore by anyone who steals one:
 *  - it calls a FIXED host. No URL ever comes from a request, so it cannot be
 *    turned into a server-side request forger or made to send the credentials
 *    anywhere else;
 *  - it is read-only against the provider;
 *  - it reports a fixed, sanitised message. It never returns the provider's
 *    response body and never echoes a credential back, so a wrong key cannot be
 *    used to read anything out of the error.
 */
interface Tester
{
    /**
     * @param  array<string, mixed>  $values  field name => value, candidate values merged over what is saved
     * @param  ?string  $target  which integration within the group, when a group holds several
     */
    public function test(array $values, ?string $target = null): TestResult;
}
