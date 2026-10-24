<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\PaymentIntent;
use App\Services\Delivery\ServiceLevel;
use App\Services\Payments\PaymentGatewayManager;
use App\Services\Pricing\CartPricingService;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Step one of a prepaid checkout: the server prices the cart and commits to
 * that number, then asks the gateway to open a payment for exactly it.
 *
 * The storefront renders the breakdown this returns rather than computing its
 * own, which is also what closes the old gap where the drawer showed a flat ₹99
 * shipping fee and checkout charged a live carrier quote.
 */
class PaymentIntentController extends Controller
{
    public function store(Request $request, CartPricingService $pricing, PaymentGatewayManager $gateways)
    {
        $validated = $request->validate([
            // Optional: which enabled gateway to pay with. Omit for the default.
            'gateway' => 'nullable|string|max:40',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|uuid|exists:products,id',
            'items.*.variant_id' => 'nullable|uuid',
            'items.*.quantity' => 'required|integer|min:1|max:'.CartPricingService::MAX_QUANTITY_PER_LINE,
            // What the shopper picked: {group_key: [choice ids] | number}.
            'items.*.options' => 'nullable|array',
            'pincode' => 'required|string|regex:/^[0-9]{6}$/',
            'payment_method' => 'required|in:UPI,CARD,NETBANKING',
            'coupon_code' => 'nullable|string',
            'use_wallet' => 'nullable|boolean',
            'redeem_points' => 'nullable|integer|min:0',
            'service_level' => 'nullable|in:'.implode(',', ServiceLevel::ALL),
        ]);

        $user = $request->user();

        $cart = $pricing->price($validated['items'], $user, [
            'coupon_code' => $validated['coupon_code'] ?? null,
            'pincode' => $validated['pincode'],
            'payment_method' => $validated['payment_method'],
            'service_level' => $validated['service_level'] ?? ServiceLevel::STANDARD,
            'redeem_points' => $validated['redeem_points'] ?? null,
            'use_wallet' => $validated['use_wallet'] ?? false,
        ]);

        $fingerprint = PaymentIntent::fingerprint(
            $cart,
            $validated['payment_method'],
            $validated['pincode'],
        );

        if ($cart->payablePaise() === 0) {
            // Nothing to collect — the wallet, points and coupon covered it all.
            // No gateway can charge ₹0, so no gateway is involved; checkout
            // accepts this intent only because its amount is exactly zero.
            $provider = 'none';
            $providerIntent = ['id' => 'none_'.Str::uuid(), 'client' => []];
        } else {
            $gateway = $gateways->forNewPayment($validated['gateway'] ?? null);
            $provider = $gateway->key();
            $providerIntent = $gateway->createIntent(
                $cart->total,
                'cart-'.$user->id,
                ['user_id' => $user->id, 'fingerprint' => $fingerprint],
            );
        }

        $intent = PaymentIntent::create([
            'user_id' => $user->id,
            'provider_intent_id' => $providerIntent['id'],
            'provider' => $provider,
            'amount_paise' => $cart->payablePaise(),
            'cart_fingerprint' => $fingerprint,
            'status' => 'CREATED',
            'expires_at' => now()->addMinutes(PaymentIntent::TTL_MINUTES),
        ]);

        return response()->json([
            'status' => 'success',
            'data' => [
                'payment_intent_id' => $intent->id,
                'provider_intent_id' => $intent->provider_intent_id,
                'provider' => $intent->provider,
                // Public, non-secret settings the gateway's client SDK needs
                // (a publishable key, say). Opaque to the API; each client
                // hands it to the SDK for `provider`.
                'client' => $providerIntent['client'] ?? [],
                'amount_paise' => $intent->amount_paise,
                'expires_at' => $intent->expires_at,
                // The authoritative breakdown — render this, don't recompute it.
                'breakdown' => $cart->toArray(),
            ],
        ], 201);
    }
}
