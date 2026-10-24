<?php

namespace App\Services\Delivery;

/**
 * One bookable delivery option from one carrier.
 *
 * Prices are in paise throughout. Money in floats is how you end up with an
 * order total that is off by a rupee and nobody can say why.
 */
class DeliveryQuote
{
    public function __construct(
        public readonly string $carrier,        // 'porter', 'rapido', 'shiprocket'…
        public readonly string $carrierLabel,   // 'Porter — 2 Wheeler'
        public readonly string $serviceLevel,   // ServiceLevel::*
        public readonly int $pricePaise,
        public readonly int $etaMinutes,
        public readonly bool $codSupported,
        public readonly ?string $serviceCode = null, // carrier's own SKU for the service
        public readonly bool $sandbox = false,
        public readonly array $raw = [],
    ) {}

    /** The same option, later by [minutes] - the time to prepare the order first. */
    public function withExtraMinutes(int $minutes): self
    {
        if ($minutes <= 0) {
            return $this;
        }

        return new self(
            $this->carrier,
            $this->carrierLabel,
            $this->serviceLevel,
            $this->pricePaise,
            $this->etaMinutes + $minutes,
            $this->codSupported,
            $this->serviceCode,
            $this->sandbox,
            $this->raw,
        );
    }

    public function toArray(): array
    {
        return [
            'carrier' => $this->carrier,
            'carrier_label' => $this->carrierLabel,
            'service_level' => $this->serviceLevel,
            'service_code' => $this->serviceCode,
            'price_paise' => $this->pricePaise,
            'price' => round($this->pricePaise / 100, 2),
            'eta_minutes' => $this->etaMinutes,
            'eta_label' => $this->etaLabel(),
            'cod_supported' => $this->codSupported,
            'sandbox' => $this->sandbox,
        ];
    }

    public function etaLabel(): string
    {
        if ($this->etaMinutes < 90) {
            return "{$this->etaMinutes} min";
        }
        if ($this->etaMinutes < 60 * 24) {
            $hours = (int) round($this->etaMinutes / 60);

            return $hours === 1 ? '1 hour' : "$hours hours";
        }

        $days = (int) ceil($this->etaMinutes / (60 * 24));

        return $days === 1 ? 'Tomorrow' : "$days days";
    }
}
