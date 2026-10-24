<?php

namespace App\Integrations;

/**
 * Keeps an admin-supplied host from pointing the server at its own network.
 *
 * Mail and storage endpoints are hosts an admin types in, and the server then
 * connects to them carrying credentials. Without a check, a hijacked admin session
 * could aim the server at an internal service (a database, a cloud metadata
 * endpoint) and read what comes back in an error message, or probe which internal
 * ports are open.
 *
 * Only public addresses pass. A self-hosted setup that really does live on a
 * private network (a MinIO next to the app, say) is an operator decision made in
 * the server's own environment — INTEGRATIONS_ALLOW_PRIVATE_HOSTS=true — never
 * something an admin session can switch on.
 */
final class HostGuard
{
    /** @return ?string why the host is refused, or null when it is fine */
    public static function problem(string $host): ?string
    {
        $host = strtolower(trim($host));

        if ($host === '' || preg_match('/[^a-z0-9.\-:\[\]]/', $host)) {
            return 'That does not look like a host name.';
        }

        if (config('integrations.allow_private_hosts')) {
            return null;
        }

        $ips = filter_var($host, FILTER_VALIDATE_IP) ? [$host] : self::resolve($host);

        if ($ips === []) {
            return 'That host could not be found.';
        }

        foreach ($ips as $ip) {
            // A public address is neither private nor reserved (loopback, link-local,
            // the 169.254.169.254 metadata address, ::1, fc00::/7 …).
            if (! filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) {
                return 'That host resolves to a private or reserved address, which is not allowed.';
            }
        }

        return null;
    }

    /** @return list<string> */
    public static function resolve(string $host): array
    {
        $ips = gethostbynamel($host) ?: [];

        foreach (@dns_get_record($host, DNS_AAAA) ?: [] as $record) {
            if (isset($record['ipv6'])) {
                $ips[] = $record['ipv6'];
            }
        }

        return array_values(array_unique($ips));
    }
}
