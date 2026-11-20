<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use App\Services\Import\AiProductExtractor;
use App\Services\Import\Documents\DocxReader;
use App\Services\Import\Documents\XlsxReader;
use App\Services\Import\GeminiClient;
use App\Services\Import\ImportVerifier;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;
use ZipArchive;

/**
 * Product import from files: spreadsheets and CSV read exactly, Word and PDF and
 * photos read by AI, every result checked against its source and the catalogue
 * before the owner sees it.
 */
class ProductImportTest extends TestCase
{
    use RefreshDatabase;

    private const PARSE = '/api/v1/admin/products/import/parse';

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
    }

    private function withKey(?string $key): void
    {
        config(['services.gemini.key' => $key, 'services.gemini.model' => 'gemini-test']);
        app()->forgetInstance(AiProductExtractor::class);
        app()->forgetInstance(GeminiClient::class);
    }

    private function parse(array $data)
    {
        return $this->actingAs($this->admin(), 'sanctum')->post(self::PARSE, $data, ['Accept' => 'application/json']);
    }

    private function csv(string $name, string $body): UploadedFile
    {
        return UploadedFile::fake()->createWithContent($name, $body);
    }

    /** A minimal but real .xlsx, built the way Excel stores one. */
    private function xlsx(array $sheets): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'xl').'.xlsx';
        $zip = new ZipArchive();
        $zip->open($path, ZipArchive::CREATE | ZipArchive::OVERWRITE);

        $strings = [];
        $sheetXml = [];
        foreach ($sheets as $rows) {
            $xml = '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>';
            foreach ($rows as $r => $cells) {
                $xml .= '<row r="'.($r + 1).'">';
                foreach ($cells as $c => $value) {
                    $ref = chr(65 + $c).($r + 1);
                    if (is_string($value)) {
                        $strings[] = $value;
                        $xml .= '<c r="'.$ref.'" t="s"><v>'.(count($strings) - 1).'</v></c>';
                    } else {
                        $xml .= '<c r="'.$ref.'"><v>'.$value.'</v></c>';
                    }
                }
                $xml .= '</row>';
            }
            $sheetXml[] = $xml.'</sheetData></worksheet>';
        }

        $zip->addFromString('xl/sharedStrings.xml', '<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            .implode('', array_map(fn ($s) => '<si><t>'.htmlspecialchars($s).'</t></si>', $strings)).'</sst>');

        $book = '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>';
        $rels = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">';
        foreach ($sheetXml as $i => $xml) {
            $n = $i + 1;
            $book .= '<sheet name="Sheet'.$n.'" sheetId="'.$n.'" r:id="rId'.$n.'"/>';
            $rels .= '<Relationship Id="rId'.$n.'" Target="worksheets/sheet'.$n.'.xml"/>';
            $zip->addFromString("xl/worksheets/sheet{$n}.xml", $xml);
        }
        $zip->addFromString('xl/workbook.xml', $book.'</sheets></workbook>');
        $zip->addFromString('xl/_rels/workbook.xml.rels', $rels.'</Relationships>');
        $zip->close();

        return new UploadedFile($path, 'prices.xlsx', null, null, true);
    }

    private function docx(string $bodyXml, string $name = 'catalogue.docx'): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'dx').'.docx';
        $zip = new ZipArchive();
        $zip->open($path, ZipArchive::CREATE | ZipArchive::OVERWRITE);
        $zip->addFromString('word/document.xml', '<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>'.$bodyXml.'</w:body></w:document>');
        $zip->close();

        return new UploadedFile($path, $name, null, null, true);
    }

    private function geminiAnswer(array $products, string $notes = ''): array
    {
        // Fake patterns are matched anywhere in the URL, so the answer comes first.
        return [
            '*:generateContent' => Http::response([
                'candidates' => [['content' => ['parts' => [['text' => json_encode(['products' => $products, 'document_notes' => $notes])]]]]],
            ]),
            '*' => Http::response(['models' => []]),
        ];
    }

    // ── Tables are read exactly ───────────────────────────────────────────

    public function test_a_csv_with_named_columns_is_read_exactly_with_no_ai(): void
    {
        $this->withKey(null);
        $category = Category::factory()->create(['name' => 'Footwear']);

        $response = $this->parse(['files' => [$this->csv('list.csv', "Name,Selling Price,MRP,Category,Stock\nCanvas Shoe,1499,2499,Footwear,12\nLeather Boot,3499,4999,Footwear,3\n")]]);

        $response->assertOk();
        $rows = $response->json('data.rows');
        $this->assertCount(2, $rows);
        $this->assertSame('Canvas Shoe', $rows[0]['title']);
        $this->assertEquals(1499, $rows[0]['price']);
        $this->assertEquals(2499, $rows[0]['mrp']);
        $this->assertSame($category->id, $rows[0]['category_id']);
        $this->assertSame(12, $rows[0]['variants'][0]['stock']);
        $this->assertSame('table', $response->json('data.driver'));
        $this->assertTrue($rows[0]['importable']);
    }

    public function test_a_csv_with_commas_inside_quoted_cells_is_still_a_table(): void
    {
        $this->withKey(null);
        Category::factory()->create(['name' => 'Footwear']);

        // The sizes and colours cells hold commas of their own, so the lines have different comma counts.
        $csv = "Name,Price,MRP,Category,Size,Colour,Stock\n"
            ."Trail Shoe,2499,3499,Footwear,\"6,7,8,9\",\"Black,Blue\",12\n"
            ."Slip On,999,1499,Footwear,\"7,8\",Red,5\n";
        $response = $this->parse(['files' => [$this->csv('list.csv', $csv)]]);

        $response->assertOk();
        $rows = $response->json('data.rows');
        $this->assertCount(2, $rows);
        $this->assertSame('table', $response->json('data.driver'));
        $this->assertSame('Trail Shoe', $rows[0]['title']);
        $this->assertEquals(2499, $rows[0]['price']);
        // 4 sizes x 2 colours, and 2 sizes x 1 colour.
        $this->assertCount(8, $rows[0]['variants']);
        $this->assertCount(2, $rows[1]['variants']);
        $this->assertTrue($rows[0]['importable']);
    }

    public function test_title_lines_above_the_table_are_skipped(): void
    {
        $this->withKey(null);
        Category::factory()->create(['name' => 'Footwear']);

        $csv = "ACME TRADERS\nPrice list October\n\nProduct,Price,Category\nCanvas Shoe,1499,Footwear\n";
        $rows = $this->parse(['files' => [$this->csv('list.csv', $csv)]])->json('data.rows');

        $this->assertCount(1, $rows);
        $this->assertSame('Canvas Shoe', $rows[0]['title']);
    }

    public function test_an_excel_workbook_is_read_sheet_by_sheet(): void
    {
        $this->withKey(null);
        Category::factory()->create(['name' => 'Footwear']);
        Category::factory()->create(['name' => 'Bags']);

        $file = $this->xlsx([
            [['Product', 'Price', 'MRP', 'Category'], ['Canvas Shoe', 1499, 2499, 'Footwear']],
            [['Product', 'Price', 'MRP', 'Category'], ['Tote Bag', 799.5, 1299, 'Bags']],
        ]);

        $response = $this->parse(['files' => [$file]]);

        $rows = $response->json('data.rows');
        $this->assertSame(['Canvas Shoe', 'Tote Bag'], array_column($rows, 'title'));
        $this->assertEquals(799.5, $rows[1]['price']);
        $this->assertStringContainsString('prices.xlsx', $rows[0]['source']);
    }

    public function test_the_excel_reader_keeps_columns_in_place_across_blank_cells(): void
    {
        $file = $this->xlsx([[['Name', 'Colour', 'Price'], ['Kurta', '', 999]]]);

        $read = XlsxReader::read($file->getRealPath());

        $this->assertSame("Name\tColour\tPrice\nKurta\t\t999", $read['sheets'][0]['text']);
    }

    public function test_a_file_that_is_not_a_workbook_is_reported_not_crashed_on(): void
    {
        $this->withKey(null);
        $fake = UploadedFile::fake()->createWithContent('broken.xlsx', 'this is not a zip');

        $response = $this->parse(['files' => [$fake]]);

        $response->assertOk();
        $this->assertSame([], $response->json('data.rows'));
        $this->assertStringContainsString('broken.xlsx', $response->json('data.problems.0'));
    }

    // ── Word and loose text ───────────────────────────────────────────────

    public function test_word_text_and_tables_are_extracted_in_order(): void
    {
        $w = fn ($t) => '<w:r><w:t>'.$t.'</w:t></w:r>';
        $file = $this->docx(
            '<w:p>'.$w('Spring range').'</w:p>'
            .'<w:p><w:pPr><w:numPr/></w:pPr>'.$w('Pure cotton').'</w:p>'
            .'<w:tbl><w:tr><w:tc><w:p>'.$w('Kurta').'</w:p></w:tc><w:tc><w:p>'.$w('₹999').'</w:p></w:tc></w:tr></w:tbl>'
        );

        $this->assertSame("Spring range\n- Pure cotton\nKurta | ₹999", DocxReader::read($file->getRealPath()));
    }

    public function test_a_word_catalogue_without_a_key_still_yields_rows_from_its_text(): void
    {
        $this->withKey(null);
        Category::factory()->create(['name' => 'Ethnic']);
        $w = fn ($t) => '<w:r><w:t>'.$t.'</w:t></w:r>';
        $file = $this->docx('<w:p>'.$w('Handwoven Cotton Kurta — ₹1,299 (MRP ₹2,199), sizes S/M/L').'</w:p>');

        $rows = $this->parse(['files' => [$file]])->json('data.rows');

        $this->assertCount(1, $rows);
        $this->assertEquals(1299, $rows[0]['price']);
        $this->assertEquals(2199, $rows[0]['mrp']);
        $this->assertCount(3, $rows[0]['variants']);
    }

    // ── Photos and PDFs need the AI ───────────────────────────────────────

    public function test_photos_without_a_key_say_what_is_needed(): void
    {
        $this->withKey(null);
        Http::fake();

        $response = $this->parse(['files' => [UploadedFile::fake()->image('shoe.jpg', 800, 800)]]);

        $response->assertOk();
        $this->assertSame([], $response->json('data.rows'));
        $this->assertStringContainsString('Gemini API key', $response->json('data.problems.0'));
        $this->assertFalse($response->json('data.ai_available'));
        Http::assertNothingSent();
    }

    public function test_a_photo_is_read_by_ai_and_kept_as_the_products_picture(): void
    {
        Storage::fake('media');
        $this->withKey('test-key');
        Http::fake($this->geminiAnswer([[
            'title' => 'CANVAS LOW TOP SNEAKER',
            'brand' => 'Acme',
            'category' => 'Footwear',
            'description' => 'White canvas sneaker with a rubber sole.',
            'description_written_by_ai' => true,
            'features' => ['Rubber sole', 'Machine wash, cold'],
            'specifications' => [['title' => 'General', 'rows' => [['label' => 'Upper', 'value' => 'Canvas']]]],
            'manufacturer' => ['country_of_origin' => 'India'],
            'price' => 1499,
            'weight_grams' => 600,
            'variants' => [
                ['color' => 'White', 'size' => 'UK 7', 'stock' => 4],
                ['color' => 'White', 'size' => 'UK 8', 'stock' => 6, 'price' => 1599],
                ['color' => 'White', 'size' => 'UK 8', 'stock' => 9],
            ],
            'photo_numbers' => [1],
            'unsure' => ['price'],
        ]]));
        Category::factory()->create(['name' => 'Footwear']);

        $response = $this->parse(['files' => [UploadedFile::fake()->image('shoe.jpg', 900, 900)]]);

        $response->assertOk();
        $row = $response->json('data.rows.0');

        $this->assertSame('Canvas Low Top Sneaker', $row['title']);
        $this->assertSame('Acme', $row['brand']);
        $this->assertNotNull($row['category_id']);
        $this->assertSame(['Rubber sole', 'Machine wash, cold'], $row['features']);
        $this->assertSame('Canvas', $row['specifications'][0]['rows'][0]['value']);
        $this->assertSame(['country_of_origin' => 'India'], $row['manufacturer']);
        $this->assertSame(600, $row['weight_grams']);
        $this->assertCount(2, $row['variants'], 'the repeated UK 8 is one variant');
        $this->assertEquals(1599, $row['variants'][1]['price']);
        $this->assertCount(1, $row['images']);
        Storage::disk('media')->assertExists('uploads/'.basename($row['images'][0]));
        $this->assertLessThanOrEqual(0.4, $row['confidence']['price'], 'a field the model was unsure of is flagged');

        $issues = implode(' | ', $row['issues']);
        $this->assertStringContainsString('written by AI', $issues);
    }

    public function test_the_request_to_google_carries_the_photo_the_schema_and_the_key_in_a_header(): void
    {
        Storage::fake('media');
        $this->withKey('secret-key-123');
        Http::fake($this->geminiAnswer([]));

        $this->parse(['files' => [UploadedFile::fake()->image('a.png', 300, 300)], 'hint' => 'All of these are from Acme']);

        Http::assertSent(function ($request) {
            if (! str_contains($request->url(), ':generateContent')) {
                return false;
            }
            $body = $request->data();

            return ! str_contains($request->url(), 'secret-key-123')
                && $request->header('x-goog-api-key')[0] === 'secret-key-123'
                && str_contains($request->url(), 'gemini-test')
                && isset($body['generationConfig']['responseSchema'])
                && $body['generationConfig']['temperature'] === 0
                && isset($body['contents'][0]['parts'][1]['inline_data']['data'])
                && str_contains($body['systemInstruction']['parts'][0]['text'], 'All of these are from Acme');
        });
    }

    public function test_one_product_and_its_photos_belong_together_even_if_the_ai_does_not_say_so(): void
    {
        Storage::fake('media');
        $this->withKey('test-key');
        Http::fake($this->geminiAnswer([['title' => 'Steel Bottle', 'price' => 399]]));

        $rows = $this->parse(['files' => [
            UploadedFile::fake()->image('front.jpg', 400, 400),
            UploadedFile::fake()->image('side.jpg', 400, 400),
        ]])->json('data.rows');

        $this->assertCount(2, $rows[0]['images']);
    }

    public function test_a_photo_of_a_price_list_is_read_but_not_kept_as_a_product_picture(): void
    {
        Storage::fake('media');
        $this->withKey('test-key');
        Http::fake($this->geminiAnswer([['title' => 'Steel Bottle', 'price' => 399, 'photo_numbers' => []], ['title' => 'Copper Jug', 'price' => 899, 'photo_numbers' => []]]));

        $rows = $this->parse(['files' => [UploadedFile::fake()->image('pricelist.jpg', 400, 400)]])->json('data.rows');

        $this->assertCount(2, $rows);
        $this->assertSame([], $rows[0]['images']);
        $this->assertSame([], Storage::disk('media')->allFiles());
    }

    public function test_a_failing_ai_call_is_explained_not_a_500(): void
    {
        $this->withKey('bad-key');
        Http::fake([
            'generativelanguage.googleapis.com/*' => Http::response(['error' => ['message' => 'API key not valid']], 400),
        ]);

        $response = $this->parse(['files' => [UploadedFile::fake()->image('a.jpg', 200, 200)]]);

        $response->assertOk();
        $this->assertSame([], $response->json('data.rows'));
        $this->assertStringContainsString('rejected the Gemini API key', $response->json('data.problems.0'));
    }

    // ── Accuracy checks ───────────────────────────────────────────────────

    public function test_a_price_that_is_not_in_the_document_is_flagged_for_checking(): void
    {
        $this->withKey('test-key');
        Http::fake($this->geminiAnswer([
            ['title' => 'Cotton Kurta', 'price' => 999, 'mrp' => 1999],
            ['title' => 'Silk Saree', 'price' => 7777],
        ]));

        $rows = $this->parse(['text' => "Cotton Kurta now only Rs. 999 (MRP 1,999)\nSilk Saree at 4,500 each"])->json('data.rows');

        $this->assertSame([], array_filter($rows[0]['issues'], fn ($i) => str_contains($i, 'not found')));
        $this->assertNotEmpty(array_filter($rows[1]['issues'], fn ($i) => str_contains($i, 'was not found in the file')));
        $this->assertLessThan(0.5, $rows[1]['confidence']['price']);
    }

    public function test_indian_number_styles_are_recognised_in_the_source(): void
    {
        $numbers = ImportVerifier::numbersIn('Price ₹1,25,000.50 and Rs. 999/-');

        $this->assertArrayHasKey('125000.5', $numbers);
        $this->assertArrayHasKey('999', $numbers);
    }

    public function test_adjacent_csv_prices_are_two_numbers_not_one(): void
    {
        $numbers = ImportVerifier::numbersIn("Canvas Shoe,1499,2499,Footwear
Boot,3499,4999,12");

        foreach (['1499', '2499', '3499', '4999', '12'] as $price) {
            $this->assertArrayHasKey($price, $numbers);
        }
    }

    public function test_prices_read_exactly_from_a_table_raise_no_not_found_warning(): void
    {
        $this->withKey(null);
        Category::factory()->create(['name' => 'Footwear']);

        $rows = $this->parse(['files' => [$this->csv('l.csv', "Name,Price,MRP,Category
Canvas Shoe,1499,2499,Footwear
")]])->json('data.rows');

        $this->assertSame([], array_filter($rows[0]['issues'], fn ($i) => str_contains($i, 'not found')));
    }

    public function test_a_product_already_in_the_catalogue_is_called_out(): void
    {
        $this->withKey(null);
        $category = Category::factory()->create(['name' => 'Footwear']);
        Product::factory()->create(['title' => 'Canvas Low Top Sneaker', 'category_id' => $category->id]);

        $rows = $this->parse(['files' => [$this->csv('l.csv', "Name,Price,Category\nCanvas Low-Top Sneaker,1499,Footwear\n")]])->json('data.rows');

        $this->assertNotEmpty(array_filter($rows[0]['issues'], fn ($i) => str_contains($i, 'already have')));
        $this->assertNotNull($rows[0]['possible_duplicate']);
    }

    public function test_a_sku_that_is_already_taken_is_left_blank_with_a_note(): void
    {
        $this->withKey(null);
        $category = Category::factory()->create(['name' => 'Footwear']);
        $existing = Product::factory()->create(['category_id' => $category->id]);
        ProductVariant::create(['product_id' => $existing->id, 'sku' => 'SHOE-1', 'size' => 'M', 'stock' => 1]);

        $rows = $this->parse(['files' => [$this->csv('l.csv', "Name,Price,Category,SKU\nBrand New Boot,1499,Footwear,SHOE-1\n")]])->json('data.rows');

        $this->assertNull($rows[0]['variants'][0]['sku']);
        $this->assertNotEmpty(array_filter($rows[0]['issues'], fn ($i) => str_contains($i, 'SKU SHOE-1')));
    }

    public function test_a_category_the_store_does_not_have_is_not_invented(): void
    {
        $this->withKey(null);
        Category::factory()->create(['name' => 'Footwear']);

        $rows = $this->parse(['files' => [$this->csv('l.csv', "Name,Price,Category\nLava Lamp,1200,Home Decor\n")]])->json('data.rows');

        $this->assertNull($rows[0]['category_id']);
        $this->assertSame('Home Decor', $rows[0]['category_hint']);
        $this->assertFalse($rows[0]['importable']);
    }

    public function test_the_chosen_category_fills_in_rows_the_reader_could_not_place(): void
    {
        $this->withKey(null);
        $category = Category::factory()->create(['name' => 'Footwear']);

        $rows = $this->parse([
            'files' => [$this->csv('l.csv', "Name,Price,Category\nLava Lamp,1200,Home Decor\n")],
            'category_id' => $category->id,
        ])->json('data.rows');

        $this->assertSame($category->id, $rows[0]['category_id']);
        $this->assertTrue($rows[0]['importable']);
    }

    // ── Models, access, limits ────────────────────────────────────────────

    public function test_the_newest_plain_flash_model_is_chosen_from_what_the_key_can_see(): void
    {
        $generate = ['generateContent'];
        $models = [
            ['name' => 'models/gemini-2.5-flash', 'supportedGenerationMethods' => $generate],
            ['name' => 'models/gemini-3.0-flash', 'supportedGenerationMethods' => $generate],
            ['name' => 'models/gemini-3.5-flash-lite', 'supportedGenerationMethods' => $generate],
            ['name' => 'models/gemini-4.0-flash-preview-05-20', 'supportedGenerationMethods' => $generate],
            ['name' => 'models/gemini-3.9-flash', 'supportedGenerationMethods' => ['embedContent']],
            ['name' => 'models/gemini-2.5-pro', 'supportedGenerationMethods' => $generate],
        ];

        $this->assertSame('gemini-3.0-flash', GeminiClient::newestFlash($models));
        $this->assertNull(GeminiClient::newestFlash([]));
    }

    public function test_the_model_is_looked_up_once_and_remembered(): void
    {
        Cache::flush();
        config(['services.gemini.model' => null]);
        Http::fake(['*/models*' => Http::response(['models' => [['name' => 'models/gemini-9-flash', 'supportedGenerationMethods' => ['generateContent']]]])]);

        $client = new GeminiClient('k');
        $this->assertSame('gemini-9-flash', $client->model());
        $this->assertSame('gemini-9-flash', $client->model());
        Http::assertSentCount(1);
    }

    public function test_only_staff_can_use_the_importer(): void
    {
        $customer = User::factory()->create(['role' => User::ROLE_CUSTOMER, 'status' => 'ACTIVE']);

        $this->actingAs($customer, 'sanctum')
            ->post(self::PARSE, ['text' => 'Shoe 100'], ['Accept' => 'application/json'])
            ->assertForbidden();
    }

    public function test_the_importer_needs_a_signed_in_user(): void
    {
        $this->post(self::PARSE, ['text' => 'Shoe 100'], ['Accept' => 'application/json'])->assertUnauthorized();
    }

    public function test_nothing_to_read_is_refused_plainly(): void
    {
        $this->withKey(null);

        $this->parse([])->assertStatus(422);
    }

    public function test_unsupported_files_say_what_to_do(): void
    {
        $this->withKey(null);

        $response = $this->parse(['files' => [
            UploadedFile::fake()->createWithContent('old.xls', 'x'),
            UploadedFile::fake()->createWithContent('old.doc', 'x'),
            UploadedFile::fake()->createWithContent('photo.heic', 'x'),
        ]]);

        $problems = implode(' | ', $response->json('data.problems'));
        $this->assertStringContainsString('.xlsx or .csv', $problems);
        $this->assertStringContainsString('.docx or PDF', $problems);
        $this->assertStringContainsString('HEIC', $problems);
    }

    public function test_long_text_is_split_without_cutting_a_line(): void
    {
        $text = implode("\n", array_map(fn ($i) => "Product {$i} line", range(1, 50)));

        $parts = AiProductExtractor::split($text, 200);

        $this->assertGreaterThan(1, count($parts));
        $this->assertSame($text, implode('', $parts));
        foreach ($parts as $part) {
            $this->assertLessThanOrEqual(200, mb_strlen($part));
        }
    }

    // ── Commit ────────────────────────────────────────────────────────────

    private function commitRow(array $overrides = []): array
    {
        $category = Category::first() ?? Category::factory()->create();

        return array_merge([
            'title' => 'Canvas Sneaker', 'price' => 1499, 'mrp' => 2499, 'category_id' => $category->id,
            'variants' => [['color' => 'White', 'size' => 'UK 7', 'stock' => 4, 'sku' => 'CS-7', 'price' => 1599]],
        ], $overrides);
    }

    private function commit(array $rows, string $status = 'DRAFT')
    {
        return $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/products/import/commit', ['rows' => $rows, 'status' => $status]);
    }

    public function test_commit_saves_the_whole_listing(): void
    {
        $response = $this->commit([$this->commitRow([
            'description' => 'A canvas sneaker.',
            'features' => ['Rubber sole', 'Machine wash, cold'],
            'specifications' => [['title' => 'General', 'rows' => [['label' => 'Upper', 'value' => 'Canvas'], ['label' => '', 'value' => 'dropped']]]],
            'manufacturer' => ['country_of_origin' => 'India', 'packer_name' => ''],
            'weight_grams' => 600, 'length_cm' => 30, 'width_cm' => 20, 'height_cm' => 12,
            'images' => ['https://cdn.test/a.jpg'],
        ])]);

        $response->assertCreated();
        $product = Product::with('variants')->firstOrFail();

        $this->assertSame(['Rubber sole', 'Machine wash, cold'], $product->features);
        $this->assertSame([['title' => 'General', 'rows' => [['label' => 'Upper', 'value' => 'Canvas']]]], $product->specifications);
        $this->assertSame(['country_of_origin' => 'India'], $product->manufacturer);
        $this->assertSame(600, $product->weight_grams);
        $this->assertSame(30, $product->length_cm);
        $this->assertSame(['https://cdn.test/a.jpg'], $product->images);
        $this->assertEquals(1599, $product->variants[0]->price);
        $this->assertSame('DRAFT', $product->status);
    }

    public function test_commit_leaves_a_taken_or_repeated_sku_blank_instead_of_failing(): void
    {
        $category = Category::factory()->create();
        $existing = Product::factory()->create(['category_id' => $category->id]);
        ProductVariant::create(['product_id' => $existing->id, 'sku' => 'TAKEN', 'size' => 'M', 'stock' => 1]);

        $response = $this->commit([
            $this->commitRow(['title' => 'One', 'category_id' => $category->id, 'variants' => [['size' => 'M', 'sku' => 'TAKEN', 'stock' => 1]]]),
            $this->commitRow(['title' => 'Two', 'category_id' => $category->id, 'variants' => [['size' => 'M', 'sku' => 'NEW-1', 'stock' => 1]]]),
            $this->commitRow(['title' => 'Three', 'category_id' => $category->id, 'variants' => [['size' => 'M', 'sku' => 'NEW-1', 'stock' => 1]]]),
        ]);

        $response->assertCreated();
        $this->assertSame(1, ProductVariant::where('sku', 'NEW-1')->count());
        $this->assertSame(1, ProductVariant::where('sku', 'TAKEN')->count());
        $this->assertSame(3, Product::whereIn('title', ['One', 'Two', 'Three'])->count());
    }

    public function test_going_live_needs_a_price_on_every_row(): void
    {
        $response = $this->commit([$this->commitRow(['title' => 'Free Thing', 'price' => 0, 'mrp' => 0])], 'ACTIVE');

        $response->assertStatus(422);
        $this->assertStringContainsString('Free Thing', $response->json('message'));
        $this->assertSame(0, Product::count());

        $this->commit([$this->commitRow(['title' => 'Free Thing', 'price' => 0, 'mrp' => 0])], 'DRAFT')->assertCreated();
    }
}
