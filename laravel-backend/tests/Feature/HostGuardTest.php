<?php

namespace Tests\Feature;

use App\Integrations\HostGuard;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/** An admin-typed host must never point the server at its own network. */
class HostGuardTest extends TestCase
{
    #[DataProvider('refused')]
    public function test_private_and_reserved_addresses_are_refused(string $host): void
    {
        $this->assertNotNull(HostGuard::problem($host), "{$host} should be refused");
    }

    public static function refused(): array
    {
        return [
            'loopback' => ['127.0.0.1'],
            'loopback name' => ['localhost'],
            'class A private' => ['10.0.0.5'],
            'class B private' => ['172.16.4.4'],
            'class C private' => ['192.168.1.1'],
            'cloud metadata' => ['169.254.169.254'],
            'unspecified' => ['0.0.0.0'],
            'ipv6 loopback' => ['::1'],
            'ipv6 unique local' => ['fd00::1'],
        ];
    }

    public function test_a_public_address_is_allowed(): void
    {
        $this->assertNull(HostGuard::problem('8.8.8.8'));
    }

    #[DataProvider('malformed')]
    public function test_anything_that_is_not_a_host_name_is_refused(string $host): void
    {
        $this->assertNotNull(HostGuard::problem($host));
    }

    public static function malformed(): array
    {
        return [
            'empty' => [''],
            'path' => ['example.com/admin'],
            'query' => ['example.com?x=1'],
            'credentials' => ['user:pass@example.com'],
            'space' => ['exam ple.com'],
            'scheme' => ['http://example.com'],
        ];
    }

    public function test_an_unresolvable_name_is_refused(): void
    {
        $this->assertNotNull(HostGuard::problem('this-host-does-not-exist.invalid'));
    }

    public function test_the_operator_can_allow_private_hosts_but_config_is_the_only_switch(): void
    {
        $this->assertNotNull(HostGuard::problem('10.0.0.5'));

        config(['integrations.allow_private_hosts' => true]);
        $this->assertNull(HostGuard::problem('10.0.0.5'));

        // Still not a host name, whatever the switch says.
        $this->assertNotNull(HostGuard::problem('10.0.0.5/x'));
    }

    public function test_the_switch_is_environment_only(): void
    {
        // Not a registry field, so no admin session can reach it.
        foreach (\App\Integrations\Registry::fields() as $field) {
            $this->assertNotContains('integrations.allow_private_hosts', $field->config);
        }
    }
}
