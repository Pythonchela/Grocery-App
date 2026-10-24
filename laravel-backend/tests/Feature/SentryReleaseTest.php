<?php

namespace Tests\Feature;

use App\Monitoring\Release;
use Tests\TestCase;

/** The release tag must come from the checkout without running anything or trusting odd input. */
class SentryReleaseTest extends TestCase
{
    private string $dir;

    private const SHA = '0123456789abcdef0123456789abcdef01234567';

    protected function setUp(): void
    {
        parent::setUp();

        $this->dir = sys_get_temp_dir().'/gitdir-'.bin2hex(random_bytes(4));
        mkdir($this->dir.'/refs/heads', 0777, true);
    }

    protected function tearDown(): void
    {
        foreach (glob($this->dir.'/{,refs/heads/}*', GLOB_BRACE) ?: [] as $f) {
            is_file($f) && unlink($f);
        }
        @rmdir($this->dir.'/refs/heads');
        @rmdir($this->dir.'/refs');
        @rmdir($this->dir);

        parent::tearDown();
    }

    public function test_a_branch_checkout_uses_the_loose_ref(): void
    {
        file_put_contents($this->dir.'/HEAD', "ref: refs/heads/main\n");
        file_put_contents($this->dir.'/refs/heads/main', self::SHA."\n");

        $this->assertSame('0123456789ab', Release::detect($this->dir));
    }

    public function test_a_detached_head_is_the_commit_itself(): void
    {
        file_put_contents($this->dir.'/HEAD', self::SHA."\n");

        $this->assertSame('0123456789ab', Release::detect($this->dir));
    }

    public function test_packed_refs_are_read_when_there_is_no_loose_ref(): void
    {
        file_put_contents($this->dir.'/HEAD', "ref: refs/heads/main\n");
        file_put_contents($this->dir.'/packed-refs', "# pack-refs\n".self::SHA." refs/heads/main\n");

        $this->assertSame('0123456789ab', Release::detect($this->dir));
    }

    public function test_anything_unexpected_gives_null_rather_than_an_error(): void
    {
        $this->assertNull(Release::detect($this->dir.'/nope'), 'no checkout');

        file_put_contents($this->dir.'/HEAD', "ref: refs/heads/../../../etc/passwd\n");
        $this->assertNull(Release::detect($this->dir), 'a path escape is refused');

        file_put_contents($this->dir.'/HEAD', "ref: not-a-ref\n");
        $this->assertNull(Release::detect($this->dir));

        file_put_contents($this->dir.'/HEAD', "ref: refs/heads/main\n");
        file_put_contents($this->dir.'/refs/heads/main', "not a sha\n");
        $this->assertNull(Release::detect($this->dir));

        file_put_contents($this->dir.'/HEAD', "garbage\n");
        $this->assertNull(Release::detect($this->dir));
    }

    public function test_this_repository_resolves_to_a_release(): void
    {
        $this->assertMatchesRegularExpression('/^[0-9a-f]{12}$/', (string) Release::detect());
    }
}
