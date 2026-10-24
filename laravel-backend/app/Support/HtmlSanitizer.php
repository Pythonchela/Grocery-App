<?php

namespace App\Support;

use DOMDocument;
use DOMElement;
use DOMNode;

/**
 * Cleans rich-text descriptions down to a small, safe set of tags.
 *
 * A seller or admin writes the description in an editor, and it is shown to
 * every shopper, in a web page and in the app. Whatever the editor produced, or
 * whatever was pasted in, only the formatting below survives: no scripts, no
 * styles, no event handlers, no images or iframes, no attributes at all except a
 * checked link target. It is rebuilt from the parsed text rather than patched
 * with regular expressions, so malformed markup cannot slip something through.
 *
 * The app renders exactly this set, so the two stay in step.
 */
final class HtmlSanitizer
{
    /** Tags kept as they are. */
    private const ALLOWED = ['p', 'br', 'strong', 'em', 'u', 's', 'ul', 'ol', 'li', 'h2', 'h3', 'h4', 'blockquote', 'hr', 'a'];

    /** Tags that are the same thing under another name. */
    private const RENAME = ['b' => 'strong', 'i' => 'em', 'strike' => 's', 'del' => 's', 'h1' => 'h2', 'h5' => 'h4', 'h6' => 'h4', 'div' => 'p'];

    /** Tags whose contents must go too, not just the tag. */
    private const DROP_WITH_CONTENT = [
        'script', 'style', 'iframe', 'object', 'embed', 'noscript', 'template', 'svg', 'math',
        'form', 'textarea', 'select', 'button', 'input', 'head', 'title', 'meta', 'link', 'base',
    ];

    private const LINK_SCHEMES = ['http', 'https', 'mailto', 'tel'];

    /** Clean markup, or null when nothing readable is left. */
    public static function clean(?string $html): ?string
    {
        $html = trim((string) $html);

        if ($html === '') {
            return null;
        }

        $dom = new DOMDocument('1.0', 'UTF-8');
        $previous = libxml_use_internal_errors(true);
        // The meta tag is what makes libxml read the input as UTF-8.
        $dom->loadHTML('<meta charset="utf-8"><body>'.$html.'</body>');
        libxml_clear_errors();
        libxml_use_internal_errors($previous);

        $body = $dom->getElementsByTagName('body')->item(0);
        $out = $body ? self::children($body) : '';

        // Editors leave empty paragraphs behind; they are only vertical space.
        $out = preg_replace('#<p>(\s|<br>)*</p>#u', '', $out) ?? $out;
        $out = trim($out);

        return self::toText($out) === '' ? null : $out;
    }

    /** The same content as plain text, for search, previews and clients that cannot render markup. */
    public static function toText(?string $html): string
    {
        $text = (string) $html;
        // An editor writes list items as <li><p>text</p></li>; that is one line, not two.
        $text = preg_replace('#<li>\s*<p>#i', '<li>', $text) ?? $text;
        $text = preg_replace('#</p>\s*</li>#i', '</li>', $text) ?? $text;
        $text = preg_replace('#<br\s*/?>#i', "\n", $text) ?? $text;
        $text = preg_replace('#</(p|li|h2|h3|h4|blockquote|ul|ol)>#i', "\n", $text) ?? $text;
        $text = preg_replace('#<li>#i', '• ', $text) ?? $text;
        $text = html_entity_decode(strip_tags($text), ENT_QUOTES | ENT_HTML5, 'UTF-8');
        $text = preg_replace("/[ \t]+/u", ' ', $text) ?? $text;
        $text = preg_replace("/\n[ \t]*/u", "\n", $text) ?? $text;
        $text = preg_replace("/\n{3,}/", "\n\n", $text) ?? $text;

        return trim($text);
    }

    private static function children(DOMNode $node): string
    {
        $out = '';

        foreach ($node->childNodes as $child) {
            $out .= self::node($child);
        }

        return $out;
    }

    private static function node(DOMNode $node): string
    {
        if ($node->nodeType === XML_TEXT_NODE || $node->nodeType === XML_CDATA_SECTION_NODE) {
            return htmlspecialchars($node->nodeValue ?? '', ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        }

        if (! $node instanceof DOMElement) {
            return '';   // comments, processing instructions
        }

        $name = strtolower($node->nodeName);

        if (in_array($name, self::DROP_WITH_CONTENT, true)) {
            return '';
        }

        $name = self::RENAME[$name] ?? $name;
        $inner = self::children($node);

        if (! in_array($name, self::ALLOWED, true)) {
            return $inner;   // unknown tag: keep the words, lose the tag
        }

        if ($name === 'br' || $name === 'hr') {
            return "<{$name}>";
        }

        if ($name === 'a') {
            $href = self::safeLink($node->getAttribute('href'));

            return $href === null
                ? $inner
                : '<a href="'.htmlspecialchars($href, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8').'" rel="noopener noreferrer nofollow" target="_blank">'.$inner.'</a>';
        }

        return "<{$name}>{$inner}</{$name}>";
    }

    /** A link we are willing to publish, or null. Only plain web, mail and phone links. */
    private static function safeLink(string $href): ?string
    {
        // Browsers ignore control characters and spaces inside a scheme, so
        // "java\tscript:" is still script; strip them before looking.
        $probe = strtolower(preg_replace('/[\x00-\x20\x7f]+/', '', $href) ?? '');

        if ($probe === '' || mb_strlen($href) > 2000) {
            return null;
        }

        $scheme = parse_url($probe, PHP_URL_SCHEME);

        return is_string($scheme) && in_array($scheme, self::LINK_SCHEMES, true) ? trim($href) : null;
    }
}
