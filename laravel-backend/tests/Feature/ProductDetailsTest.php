<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\Seller;
use App\Models\User;
use App\Support\HtmlSanitizer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The "all details" part of a product: a formatted description, a specification
 * table, and the manufacturer panel.
 */
class ProductDetailsTest extends TestCase
{
    use RefreshDatabase;

    // ── The cleaner ──────────────────────────────────────────────────────

    public function test_formatting_the_editor_produces_is_kept(): void
    {
        $html = '<h2>Care</h2><p>Wash <strong>cold</strong>, <em>inside out</em>.</p><ul><li>No bleach</li><li>Line dry</li></ul>';

        $this->assertSame($html, HtmlSanitizer::clean($html));
    }

    public function test_scripts_and_their_contents_are_removed(): void
    {
        $clean = HtmlSanitizer::clean('<p>Hello</p><script>alert(1)</script><style>p{display:none}</style><p>World</p>');

        $this->assertSame('<p>Hello</p><p>World</p>', $clean);
    }

    public function test_attributes_and_event_handlers_are_stripped(): void
    {
        $clean = HtmlSanitizer::clean('<p onclick="steal()" style="color:red" class="x">Hi</p>');

        $this->assertSame('<p>Hi</p>', $clean);
    }

    public function test_images_and_frames_never_get_through(): void
    {
        $clean = HtmlSanitizer::clean('<p>A</p><img src="x" onerror="alert(1)"><iframe src="https://evil.test"></iframe><p>B</p>');

        $this->assertSame('<p>A</p><p>B</p>', $clean);
    }

    public function test_links_keep_only_safe_targets_and_always_get_rel_and_target(): void
    {
        $clean = HtmlSanitizer::clean('<a href="https://example.com/care" onclick="x()">Care guide</a>');

        $this->assertSame('<a href="https://example.com/care" rel="noopener noreferrer nofollow" target="_blank">Care guide</a>', $clean);
    }

    public function test_script_links_lose_the_link_but_keep_the_words(): void
    {
        foreach (['javascript:alert(1)', "java\tscript:alert(1)", 'JaVaScRiPt:alert(1)', 'data:text/html,<script>1</script>', 'vbscript:x', '//evil.test'] as $href) {
            $clean = HtmlSanitizer::clean('<p><a href="'.htmlspecialchars($href).'">click me</a></p>');

            $this->assertSame('<p>click me</p>', $clean, "href {$href} must not survive");
        }
    }

    public function test_equivalent_tags_are_renamed_to_the_ones_the_app_draws(): void
    {
        $this->assertSame('<h2>Big</h2><p><strong>b</strong><em>i</em></p>', HtmlSanitizer::clean('<h1>Big</h1><p><b>b</b><i>i</i></p>'));
    }

    public function test_unknown_tags_are_unwrapped_not_lost(): void
    {
        $this->assertSame('<p>kept words</p>', HtmlSanitizer::clean('<p><span class="a"><font color="red">kept words</font></span></p>'));
    }

    public function test_special_characters_are_escaped_and_survive_a_round_trip(): void
    {
        $clean = HtmlSanitizer::clean('<p>Tom &amp; Jerry &lt;3 &quot;quotes&quot; ₹499</p>');

        $this->assertSame('<p>Tom &amp; Jerry &lt;3 &quot;quotes&quot; ₹499</p>', $clean);
        $this->assertSame('Tom & Jerry <3 "quotes" ₹499', HtmlSanitizer::toText($clean));
    }

    public function test_empty_or_markup_only_input_is_nothing(): void
    {
        $this->assertNull(HtmlSanitizer::clean(null));
        $this->assertNull(HtmlSanitizer::clean('   '));
        $this->assertNull(HtmlSanitizer::clean('<p></p><p><br></p>'));
        $this->assertNull(HtmlSanitizer::clean('<script>alert(1)</script>'));
    }

    public function test_plain_text_keeps_paragraphs_and_list_items(): void
    {
        $text = HtmlSanitizer::toText('<p>First para</p><p>Second<br>line</p><ul><li>One</li><li>Two</li></ul>');

        $this->assertSame("First para\nSecond\nline\n• One\n• Two", $text);
    }

    public function test_list_items_the_editor_wraps_in_paragraphs_are_still_one_line_each(): void
    {
        $text = HtmlSanitizer::toText('<ul><li><p>No bleach</p></li><li><p>Line dry</p></li></ul>');

        $this->assertSame("• No bleach\n• Line dry", $text);
    }

    // ── Storing it ───────────────────────────────────────────────────────

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'title' => 'Slim Fit Shirt',
            'category_id' => Category::factory()->create()->id,
            'brand' => 'Snitch',
            'mrp' => 999,
            'price' => 626,
            'status' => 'ACTIVE',
            'images' => ['https://example.com/a.jpg'],
            'variants' => [['color' => 'Navy', 'size' => 'M', 'sku' => 'SH-'.strtoupper(\Illuminate\Support\Str::random(6)), 'stock' => 5]],
        ], $overrides);
    }

    private function create(array $overrides = [])
    {
        return $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/products', $this->payload($overrides));
    }

    public function test_a_formatted_description_is_cleaned_and_its_plain_text_kept_alongside(): void
    {
        $response = $this->create([
            'description_html' => '<p>Soft <strong>cotton</strong>.</p><script>x()</script><ul><li>Slim fit</li></ul>',
        ])->assertCreated();

        $product = Product::findOrFail($response->json('data.id'));
        $this->assertSame('<p>Soft <strong>cotton</strong>.</p><ul><li>Slim fit</li></ul>', $product->description_html);
        $this->assertSame("Soft cotton.\n• Slim fit", $product->description, 'search and simple clients read this');
    }

    public function test_the_specification_table_is_stored_tidied(): void
    {
        $response = $this->create(['specifications' => [
            ['title' => 'General', 'rows' => [
                ['label' => ' Fabric ', 'value' => 'Polyester'],
                ['label' => 'Fit', 'value' => ''],            // half a row: dropped
                ['label' => '', 'value' => 'orphan'],         // dropped
                ['label' => 'Sleeve', 'value' => 'Full Sleeve'],
            ]],
            ['title' => 'Empty group', 'rows' => [['label' => '', 'value' => '']]],   // nothing left: dropped
            ['title' => '', 'rows' => [['label' => 'Pack of', 'value' => '1']]],       // untitled: General
        ]])->assertCreated();

        $this->assertSame([
            ['title' => 'General', 'rows' => [['label' => 'Fabric', 'value' => 'Polyester'], ['label' => 'Sleeve', 'value' => 'Full Sleeve']]],
            ['title' => 'General', 'rows' => [['label' => 'Pack of', 'value' => '1']]],
        ], $response->json('data.specifications'));
    }

    public function test_only_filled_manufacturer_fields_are_kept(): void
    {
        $response = $this->create(['manufacturer' => [
            'generic_name' => 'Shirt', 'country_of_origin' => 'India', 'packer_name' => '  ', 'manufacturer_address' => '4th Cross, Bengaluru',
        ]])->assertCreated();

        $this->assertSame(
            ['generic_name' => 'Shirt', 'country_of_origin' => 'India', 'manufacturer_address' => '4th Cross, Bengaluru'],
            $response->json('data.manufacturer'),
        );
    }

    public function test_a_product_without_any_of_it_is_still_valid(): void
    {
        $response = $this->create()->assertCreated();

        $this->assertNull($response->json('data.description_html'));
        $this->assertNull($response->json('data.specifications'));
        $this->assertNull($response->json('data.manufacturer'));
    }

    public function test_too_many_rows_or_an_oversized_description_is_refused(): void
    {
        $rows = array_fill(0, 61, ['label' => 'A', 'value' => 'B']);

        $this->create(['specifications' => [['title' => 'G', 'rows' => $rows]]])->assertStatus(422)->assertJsonValidationErrors('specifications.0.rows');
        $this->create(['description_html' => str_repeat('a', 40001)])->assertStatus(422)->assertJsonValidationErrors('description_html');
    }

    public function test_one_product_returns_everything_but_the_list_stays_light(): void
    {
        $id = $this->create([
            'description_html' => '<p>Long copy</p>',
            'specifications' => [['title' => 'General', 'rows' => [['label' => 'Fabric', 'value' => 'Cotton']]]],
            'manufacturer' => ['generic_name' => 'Shirt'],
        ])->assertCreated()->json('data.id');

        $one = $this->getJson("/api/v1/products/{$id}")->assertOk();
        $one->assertJsonPath('data.description_html', '<p>Long copy</p>');
        $one->assertJsonPath('data.specifications.0.rows.0.label', 'Fabric');
        $one->assertJsonPath('data.manufacturer.generic_name', 'Shirt');

        $row = collect($this->getJson('/api/v1/products')->assertOk()->json('data'))->firstWhere('id', $id);
        $this->assertNotNull($row);
        $this->assertArrayNotHasKey('description_html', $row);
        $this->assertArrayNotHasKey('specifications', $row);
        $this->assertArrayNotHasKey('manufacturer', $row);
        $this->assertSame('Long copy', trim($row['description']));
    }

    // ── Editing it ───────────────────────────────────────────────────────

    public function test_editing_the_plain_text_replaces_the_formatted_version(): void
    {
        $admin = $this->admin();
        $id = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/products', $this->payload(['description_html' => '<p>Old <strong>copy</strong></p>']))->json('data.id');

        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/products/{$id}", ['description' => 'A plain rewrite'])->assertOk();

        $product = Product::findOrFail($id);
        $this->assertNull($product->description_html);
        $this->assertSame('A plain rewrite', $product->description);
    }

    public function test_sending_back_the_same_plain_text_keeps_the_formatting(): void
    {
        // A simple client edits some other field and echoes the description it was given.
        $admin = $this->admin();
        $id = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/products', $this->payload(['description_html' => '<p>Soft <strong>cotton</strong></p>']))->json('data.id');
        $plain = Product::findOrFail($id)->description;

        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/products/{$id}", ['description' => $plain, 'brand' => 'Other'])->assertOk();

        $product = Product::findOrFail($id);
        $this->assertSame('<p>Soft <strong>cotton</strong></p>', $product->description_html);
        $this->assertSame('Other', $product->brand);
    }

    public function test_clearing_the_table_removes_it(): void
    {
        $admin = $this->admin();
        $id = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/products', $this->payload(['specifications' => [['title' => 'G', 'rows' => [['label' => 'A', 'value' => 'B']]]]]))->json('data.id');

        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/products/{$id}", ['specifications' => []])->assertOk();

        $this->assertNull(Product::findOrFail($id)->specifications);
    }

    public function test_a_seller_can_fill_in_the_details_of_their_own_product(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);
        Seller::factory()->create(['user_id' => $user->id, 'status' => 'ACTIVE']);

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/v1/products', $this->payload([
            'specifications' => [['title' => 'General', 'rows' => [['label' => 'Fit', 'value' => 'Slim']]]],
        ]))->assertCreated();

        $response->assertJsonPath('data.specifications.0.rows.0.value', 'Slim');
    }

    // ── Colours' own photos ──────────────────────────────────────────────

    public function test_a_colour_can_have_its_own_photos(): void
    {
        $response = $this->create(['variants' => [
            ['color' => 'Navy', 'size' => 'M', 'sku' => 'N-M-'.uniqid(), 'stock' => 3, 'images' => ['https://example.com/navy1.jpg', 'https://example.com/navy2.jpg']],
            ['color' => 'Olive', 'size' => 'M', 'sku' => 'O-M-'.uniqid(), 'stock' => 3],
        ]])->assertCreated();

        $variants = collect($this->getJson('/api/v1/products/'.$response->json('data.id'))->json('data.variants'));

        $this->assertSame(['https://example.com/navy1.jpg', 'https://example.com/navy2.jpg'], $variants->firstWhere('color', 'Navy')['images']);
        $this->assertEmpty($variants->firstWhere('color', 'Olive')['images'] ?? []);
    }

    // ── Category templates ───────────────────────────────────────────────

    public function test_a_category_can_suggest_which_specification_rows_its_products_need(): void
    {
        $admin = $this->admin();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/categories', [
            'name' => 'Shirts',
            'spec_template' => [
                ['title' => 'General', 'labels' => ['Fabric', ' Fit ', 'Fabric', '']],
                ['title' => 'Empty', 'labels' => []],
            ],
        ])->assertCreated();

        $this->assertSame([['title' => 'General', 'labels' => ['Fabric', 'Fit']]], $response->json('data.spec_template'));
    }
}
