<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Models\SupportTicket;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Help for shoppers and sellers, and the team's inbox. What matters: people see
 * only their own tickets, internal notes never reach them, the clock for a first
 * reply is kept, and the team's actions leave an audit trail.
 */
class SupportTicketsTest extends TestCase
{
    use RefreshDatabase;

    private const ADDRESS = [
        'name' => 'Priya Sharma', 'phone' => '9876543210', 'line1' => '221B Indiranagar',
        'city' => 'Bengaluru', 'state' => 'Karnataka', 'pincode' => '560038',
    ];

    private function customer(): User
    {
        return User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
    }

    private function staff(string $role = 'SUB_ADMIN'): User
    {
        return User::factory()->create(['role' => $role, 'status' => 'ACTIVE']);
    }

    private function seller(): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create(['user_id' => $user->id, 'status' => 'ACTIVE']);
    }

    private function orderFor(User $customer, Seller $seller): Order
    {
        $product = Product::factory()->pricedAt(500)->soldBy($seller)->create();
        ProductVariant::factory()->withStock(5)->create(['product_id' => $product->id]);
        $product = $product->fresh('variants');

        $number = $this->actingAs($customer, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $product->id, 'variant_id' => $product->variants->first()->id, 'quantity' => 1]],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
        ])->assertCreated()->json('data.order_number');

        return Order::where('order_number', $number)->firstOrFail();
    }

    private function open(User $user, array $extra = []): string
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/v1/support/tickets', $extra + [
            'category' => 'DELIVERY', 'subject' => 'Where is my parcel', 'message' => 'It has been a week.',
        ])->assertCreated()->json('data.id');
    }

    public function test_a_shopper_raises_a_ticket_about_their_own_order(): void
    {
        $customer = $this->customer();
        $order = $this->orderFor($customer, $this->seller());

        $response = $this->actingAs($customer, 'sanctum')->postJson('/api/v1/support/tickets', [
            'category' => 'ORDER_ISSUE', 'subject' => 'Wrong colour', 'message' => 'I got blue.', 'order_id' => $order->id,
        ])->assertCreated();

        $this->assertStringStartsWith('TKT-', $response->json('data.number'));
        $this->assertSame('OPEN', $response->json('data.status'));
        $this->assertSame($order->order_number, $response->json('data.order_number'));
        $this->assertCount(1, $response->json('data.messages'));
    }

    public function test_nobody_can_attach_or_read_someone_elses_order_or_ticket(): void
    {
        $owner = $this->customer();
        $other = $this->customer();
        $order = $this->orderFor($owner, $this->seller());
        $id = $this->open($owner);

        $this->actingAs($other, 'sanctum')->postJson('/api/v1/support/tickets', [
            'category' => 'ORDER_ISSUE', 'subject' => 'Not mine', 'message' => 'Hello there', 'order_id' => $order->id,
        ])->assertStatus(422)->assertJsonValidationErrors('order_id');

        $this->actingAs($other, 'sanctum')->getJson("/api/v1/support/tickets/{$id}")->assertNotFound();
        $this->actingAs($other, 'sanctum')->postJson("/api/v1/support/tickets/{$id}/messages", ['body' => 'hi'])->assertNotFound();
        $this->assertCount(0, $this->actingAs($other, 'sanctum')->getJson('/api/v1/support/tickets')->json('data'));
    }

    public function test_signed_out_visitors_cannot_use_support(): void
    {
        $this->postJson('/api/v1/support/tickets', [])->assertUnauthorized();
        $this->getJson('/api/v1/support/tickets')->assertUnauthorized();
    }

    public function test_a_seller_can_raise_a_ticket_and_name_an_order_with_their_goods(): void
    {
        $seller = $this->seller();
        $order = $this->orderFor($this->customer(), $seller);

        $id = $this->open($seller->user, ['category' => 'PAYOUT', 'subject' => 'Payout missing', 'order_id' => $order->id]);

        $ticket = SupportTicket::findOrFail($id);
        $this->assertSame($seller->id, $ticket->seller_id);
        $this->assertSame('HIGH', $ticket->priority, 'money questions start high');

        $stranger = $this->seller();
        $this->actingAs($stranger->user, 'sanctum')->postJson('/api/v1/support/tickets', [
            'category' => 'ORDER_ISSUE', 'subject' => 'Not mine', 'message' => 'Hello', 'order_id' => $order->id,
        ])->assertStatus(422);
    }

    public function test_the_teams_reply_stops_the_clock_notifies_and_waits_on_the_requester(): void
    {
        $customer = $this->customer();
        $id = $this->open($customer);
        $agent = $this->staff();

        $this->assertNotNull(SupportTicket::find($id)->sla_due_at);

        $this->actingAs($agent, 'sanctum')->postJson("/api/v1/admin/support/tickets/{$id}/messages", ['body' => 'Checking with the courier.'])->assertOk();

        $ticket = SupportTicket::find($id);
        $this->assertSame('WAITING_ON_REQUESTER', $ticket->status);
        $this->assertNotNull($ticket->first_response_at);
        $this->assertSame($agent->id, $ticket->assigned_to);
        $this->assertDatabaseHas('app_notifications', ['user_id' => $customer->id, 'type' => 'SUPPORT']);

        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/support/tickets/{$id}/messages", ['body' => 'Thanks'])->assertCreated();
        $this->assertSame('OPEN', SupportTicket::find($id)->status, 'their reply puts it back in the queue');
    }

    public function test_internal_notes_never_reach_the_requester(): void
    {
        $customer = $this->customer();
        $id = $this->open($customer);
        $agent = $this->staff();

        $this->actingAs($agent, 'sanctum')->postJson("/api/v1/admin/support/tickets/{$id}/messages", ['body' => 'Looks like fraud.', 'internal' => true])->assertOk();
        $this->actingAs($agent, 'sanctum')->postJson("/api/v1/admin/support/tickets/{$id}/messages", ['body' => 'We are on it.'])->assertOk();

        $mine = $this->actingAs($customer, 'sanctum')->getJson("/api/v1/support/tickets/{$id}")->assertOk();
        $this->assertStringNotContainsString('fraud', json_encode($mine->json()));
        $this->assertCount(2, $mine->json('data.messages'));

        $staffView = $this->actingAs($agent, 'sanctum')->getJson("/api/v1/admin/support/tickets/{$id}")->assertOk();
        $this->assertCount(3, $staffView->json('data.messages'));

        // A shopper cannot mark their own message internal.
        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/support/tickets/{$id}/messages", ['body' => 'ok', 'internal' => true])->assertCreated();
        $this->assertSame(0, \App\Models\SupportMessage::where('user_id', $customer->id)->where('is_internal', true)->count());
    }

    public function test_an_internal_note_does_not_count_as_answering(): void
    {
        $id = $this->open($this->customer());

        $this->actingAs($this->staff(), 'sanctum')->postJson("/api/v1/admin/support/tickets/{$id}/messages", ['body' => 'Note to self', 'internal' => true])->assertOk();

        $ticket = SupportTicket::find($id);
        $this->assertNull($ticket->first_response_at);
        $this->assertSame('OPEN', $ticket->status);
    }

    public function test_the_inbox_flags_overdue_tickets_and_filters(): void
    {
        $customer = $this->customer();
        $late = $this->open($customer, ['subject' => 'Late one here']);
        $this->open($customer, ['subject' => 'Fresh one here']);
        SupportTicket::whereKey($late)->update(['sla_due_at' => now()->subHour()]);

        $agent = $this->staff();
        $all = $this->actingAs($agent, 'sanctum')->getJson('/api/v1/admin/support/tickets')->assertOk();
        $this->assertSame(1, $all->json('counts.overdue'));
        $this->assertSame(2, $all->json('counts.unassigned'));
        $this->assertTrue(collect($all->json('data'))->firstWhere('id', $late)['overdue']);

        $this->assertCount(1, $this->actingAs($agent, 'sanctum')->getJson('/api/v1/admin/support/tickets?overdue=1')->json('data'));
        $this->assertCount(1, $this->actingAs($agent, 'sanctum')->getJson('/api/v1/admin/support/tickets?q=Fresh')->json('data'));
        $this->assertCount(0, $this->actingAs($agent, 'sanctum')->getJson('/api/v1/admin/support/tickets?kind=seller')->json('data'));

        $this->actingAs($customer, 'sanctum')->getJson('/api/v1/admin/support/tickets')->assertForbidden();
    }

    public function test_staff_assign_prioritise_and_resolve_and_it_is_audited(): void
    {
        $customer = $this->customer();
        $id = $this->open($customer);
        $agent = $this->staff();
        $colleague = $this->staff('ADMIN');

        $this->actingAs($agent, 'sanctum')->putJson("/api/v1/admin/support/tickets/{$id}", [
            'status' => 'IN_PROGRESS', 'priority' => 'URGENT', 'assigned_to' => $colleague->id,
        ])->assertOk();

        $ticket = SupportTicket::find($id);
        $this->assertSame('URGENT', $ticket->priority);
        $this->assertSame($colleague->id, $ticket->assigned_to);
        $this->assertTrue($ticket->sla_due_at->lt(now()->addHours(3)), 'urgent tightens the reply target');

        $this->actingAs($agent, 'sanctum')->putJson("/api/v1/admin/support/tickets/{$id}", ['status' => 'RESOLVED'])->assertOk();
        $this->assertNotNull(SupportTicket::find($id)->resolved_at);
        $this->assertDatabaseHas('app_notifications', ['user_id' => $customer->id, 'type' => 'SUPPORT']);
        $this->assertSame(2, AuditLog::where('action', 'support.updated')->count());

        $this->actingAs($agent, 'sanctum')->putJson("/api/v1/admin/support/tickets/{$id}", ['assigned_to' => $customer->id])->assertStatus(422);
        $this->actingAs($agent, 'sanctum')->putJson("/api/v1/admin/support/tickets/{$id}", ['status' => 'NOPE'])->assertStatus(422);
    }

    public function test_the_requester_can_close_and_rate_but_only_once_resolved(): void
    {
        $customer = $this->customer();
        $id = $this->open($customer);

        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/support/tickets/{$id}/rating", ['rating' => 5])->assertStatus(422);

        $this->actingAs($this->staff(), 'sanctum')->putJson("/api/v1/admin/support/tickets/{$id}", ['status' => 'RESOLVED'])->assertOk();
        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/support/tickets/{$id}/rating", ['rating' => 4, 'note' => 'Quick'])->assertOk();
        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/support/tickets/{$id}/rating", ['rating' => 9])->assertStatus(422);
        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/support/tickets/{$id}/close")->assertOk();

        $this->assertSame('CLOSED', SupportTicket::find($id)->status);
        $this->assertSame(4, SupportTicket::find($id)->rating);
        $this->actingAs($customer, 'sanctum')->postJson("/api/v1/support/tickets/{$id}/messages", ['body' => 'one more thing'])->assertStatus(422);
    }

    public function test_resolved_tickets_close_by_themselves_after_the_wait(): void
    {
        $id = $this->open($this->customer());
        $this->actingAs($this->staff(), 'sanctum')->putJson("/api/v1/admin/support/tickets/{$id}", ['status' => 'RESOLVED'])->assertOk();

        $this->artisan('support:close-resolved')->assertSuccessful();
        $this->assertSame('RESOLVED', SupportTicket::find($id)->status);

        SupportTicket::whereKey($id)->update(['resolved_at' => now()->subDays(8)]);
        $this->artisan('support:close-resolved')->assertSuccessful();
        $this->assertSame('CLOSED', SupportTicket::find($id)->status);
    }

    public function test_input_is_validated(): void
    {
        $customer = $this->customer();

        $this->actingAs($customer, 'sanctum')->postJson('/api/v1/support/tickets', ['category' => 'NOPE', 'subject' => 'x', 'message' => ''])
            ->assertStatus(422)->assertJsonValidationErrors(['category', 'subject', 'message']);
    }
}
