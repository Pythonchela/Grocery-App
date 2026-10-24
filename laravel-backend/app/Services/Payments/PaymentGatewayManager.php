<?php

namespace App\Services\Payments;

use App\Services\Contracts\PaymentGateway;
use App\Services\Mock\MockPaymentGateway;
use App\Services\PaymentGatewayException;

/**
 * The set of gateways this deployment can talk to.
 *
 * Two questions, kept apart on purpose:
 *
 *  - which gateway should a *new* payment use?  → `default()` / `enabled()`
 *  - which gateway took an *existing* payment?  → `driver($key)`
 *
 * The second must keep working after the first changes, which is why refunds
 * never ask for "the" gateway: they ask for the one recorded on the payment.
 */
class PaymentGatewayManager
{
    /** @var array<string, PaymentGateway> */
    private array $drivers = [];

    /**
     * @param  bool  $allowSandbox  whether the sandbox gateway may be offered for
     *                              new payments when no real one is configured.
     *                              Off in production unless explicitly enabled.
     */
    public function __construct(
        array $gateways = [],
        private ?string $defaultKey = null,
        private bool $allowSandbox = true,
    ) {
        foreach ($gateways as $gateway) {
            $this->register($gateway);
        }

        // The sandbox is always addressable — payments taken under it must stay
        // refundable — but only *offered* for new payments when nothing real is
        // configured (see enabled()).
        if (! isset($this->drivers['mock'])) {
            $this->register(new MockPaymentGateway());
        }
    }

    public function register(PaymentGateway $gateway): void
    {
        $this->drivers[$gateway->key()] = $gateway;
    }

    public function has(string $key): bool
    {
        return isset($this->drivers[$key]);
    }

    /** The gateway that took (or would take) a specific payment. */
    public function driver(string $key): PaymentGateway
    {
        return $this->drivers[$key] ?? throw new PaymentGatewayException(
            'This payment was taken through a gateway that is not currently set up, so it cannot be processed here.',
            "no driver registered for '{$key}'",
        );
    }

    /**
     * Gateways a shopper may pay with today: every real one that is configured.
     *
     * With none configured the sandbox is offered — but only where that is
     * allowed. The sandbox reports every payment as successful and moves no
     * money, so a production server that lost its keys must not quietly fall
     * back to it and accept orders nobody paid for. Cash on delivery is
     * unaffected either way.
     *
     * @return list<string>
     */
    public function enabled(): array
    {
        $real = array_values(array_filter(
            array_keys($this->drivers),
            fn (string $key) => $key !== 'mock',
        ));

        if ($real) {
            return $real;
        }

        return $this->allowSandbox ? ['mock'] : [];
    }

    /** True when a shopper can pay online at all right now. */
    public function hasOnlinePayment(): bool
    {
        return $this->enabled() !== [];
    }

    private function unavailable(string $detail): PaymentGatewayException
    {
        return new PaymentGatewayException(
            'Online payment is not available right now. Please choose cash on delivery or try again later.',
            $detail,
        );
    }

    /** The gateway new payments use unless the caller picks another enabled one. */
    public function default(): PaymentGateway
    {
        $enabled = $this->enabled();

        if ($enabled === []) {
            throw $this->unavailable('no payment gateway is configured and the sandbox is not allowed here');
        }

        if ($this->defaultKey && in_array($this->defaultKey, $enabled, true)) {
            return $this->drivers[$this->defaultKey];
        }

        return $this->drivers[$enabled[0]];
    }

    /** Resolve the gateway for a new payment, honouring an explicit choice. */
    public function forNewPayment(?string $requested = null): PaymentGateway
    {
        if ($requested === null || $requested === '') {
            return $this->default();
        }

        if ($this->enabled() === []) {
            throw $this->unavailable('no payment gateway is configured and the sandbox is not allowed here');
        }

        if (! in_array($requested, $this->enabled(), true)) {
            throw new PaymentGatewayException(
                'That payment method is not available right now.',
                "gateway '{$requested}' is not enabled",
            );
        }

        return $this->drivers[$requested];
    }
}
