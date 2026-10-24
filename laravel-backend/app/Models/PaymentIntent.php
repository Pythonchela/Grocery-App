<?php

namespace App\Models;

use App\Services\Pricing\PricedCart;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * A price the server quoted, and is prepared to be held to.
 *
 * Checkout for any prepaid method has to present one of these. It pins three
 * things at quote time — who it was for, what it costs, and which exact cart it
 * covers — so the only thing left for the client to supply at checkout is proof
 * the gateway captured it.
 */
#[Fillable([
    'user_id', 'provider_intent_id', 'provider_payment_id', 'provider', 'amount_paise',
    'cart_fingerprint', 'status', 'order_id', 'expires_at', 'paid_at',
])]
class PaymentIntent extends Model
{
    use HasFactory, HasUuids;

    /** Long enough to finish a checkout, short enough that a stale price dies. */
    public const TTL_MINUTES = 20;

    protected function casts(): array
    {
        return ['expires_at' => 'datetime', 'paid_at' => 'datetime', 'amount_paise' => 'integer'];
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Identifies the basket a quote was issued against.
     *
     * Covers everything that moves the price: the exact variants and their
     * quantities, the coupon, the delivery speed and the payment method. Change
     * any of them after quoting and the fingerprint stops matching, which is the
     * intended outcome — the old price no longer describes this cart.
     */
    public static function fingerprint(PricedCart $cart, string $paymentMethod, string $pincode): string
    {
        $parts = array_map(
            fn ($line) => $line->variant->id.':'.$line->quantity
                .($line->options === [] ? '' : ':'.$line->optionsSignature()),
            $cart->lines,
        );
        sort($parts);

        return hash('sha256', implode('|', [
            implode(',', $parts),
            $cart->coupon?->code ?? '',
            $cart->serviceLevel,
            $paymentMethod,
            $pincode,
        ]));
    }

    public function isUsable(): bool
    {
        // PAID = a webhook saw the money arrive before the customer's own
        // checkout call did; that call may still claim it.
        return in_array($this->status, ['CREATED', 'PAID'], true) && $this->expires_at->isFuture();
    }
}
