'use client';

import React, { useEffect } from 'react';
import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import {
  Bold, Italic, Underline as UnderlineIcon, Strikethrough, Heading2, Heading3,
  List, ListOrdered, Quote, Link2, Eraser, Undo2, Redo2,
} from 'lucide-react';

/**
 * A small rich-text editor for product descriptions.
 *
 * It offers only what the shopper-facing pages can show: bold, italic,
 * underline, strike, two heading sizes, bullet and numbered lists, quotes and
 * links. The server cleans whatever arrives to that same set again, so nothing
 * typed or pasted here can put a script or a style on a product page.
 *
 * `value` and `onChange` are HTML strings; an empty editor reports ''.
 */
export default function RichTextEditor({ value, onChange, placeholder = 'Write the description…', minHeight = 160 }) {
  const editor = useEditor({
    // Next renders on the server first; the editor only exists in the browser.
    immediatelyRender: false,
    extensions: [
      StarterKit.configure({
        heading: { levels: [2, 3] },
        // Not offered to shoppers, so not offered here.
        code: false,
        codeBlock: false,
        horizontalRule: false,
        link: {
          openOnClick: false,
          autolink: true,
          HTMLAttributes: { rel: 'noopener noreferrer nofollow', target: '_blank' },
        },
      }),
    ],
    content: value || '',
    editorProps: {
      attributes: {
        class: 'rich-text focus:outline-none px-4 py-3',
        style: `min-height:${minHeight}px`,
        'data-placeholder': placeholder,
      },
    },
    onUpdate: ({ editor: ed }) => onChange(ed.isEmpty ? '' : ed.getHTML()),
  });

  // A different product was opened: show its text. Typing also changes `value`
  // (through onChange), and replacing the content then would move the cursor,
  // so only a real difference from what the editor already holds is applied.
  useEffect(() => {
    if (!editor) return;
    const current = editor.isEmpty ? '' : editor.getHTML();
    if ((value || '') !== current) editor.commands.setContent(value || '', { emitUpdate: false });
  }, [value, editor]);

  if (!editor) {
    return <div className="rounded-card border border-line bg-surface-muted" style={{ minHeight: minHeight + 44 }} />;
  }

  const setLink = () => {
    const previous = editor.getAttributes('link').href || '';
    const url = window.prompt('Link address (https://…)', previous);
    if (url === null) return;
    if (url.trim() === '') {
      editor.chain().focus().extendMarkRange('link').unsetLink().run();
      return;
    }
    editor.chain().focus().extendMarkRange('link').setLink({ href: url.trim() }).run();
  };

  const tools = [
    { label: 'Bold', icon: Bold, run: () => editor.chain().focus().toggleBold().run(), active: editor.isActive('bold') },
    { label: 'Italic', icon: Italic, run: () => editor.chain().focus().toggleItalic().run(), active: editor.isActive('italic') },
    { label: 'Underline', icon: UnderlineIcon, run: () => editor.chain().focus().toggleUnderline().run(), active: editor.isActive('underline') },
    { label: 'Strikethrough', icon: Strikethrough, run: () => editor.chain().focus().toggleStrike().run(), active: editor.isActive('strike') },
    null,
    { label: 'Large heading', icon: Heading2, run: () => editor.chain().focus().toggleHeading({ level: 2 }).run(), active: editor.isActive('heading', { level: 2 }) },
    { label: 'Small heading', icon: Heading3, run: () => editor.chain().focus().toggleHeading({ level: 3 }).run(), active: editor.isActive('heading', { level: 3 }) },
    { label: 'Bulleted list', icon: List, run: () => editor.chain().focus().toggleBulletList().run(), active: editor.isActive('bulletList') },
    { label: 'Numbered list', icon: ListOrdered, run: () => editor.chain().focus().toggleOrderedList().run(), active: editor.isActive('orderedList') },
    { label: 'Quote', icon: Quote, run: () => editor.chain().focus().toggleBlockquote().run(), active: editor.isActive('blockquote') },
    { label: 'Link', icon: Link2, run: setLink, active: editor.isActive('link') },
    null,
    { label: 'Clear formatting', icon: Eraser, run: () => editor.chain().focus().unsetAllMarks().clearNodes().run() },
    { label: 'Undo', icon: Undo2, run: () => editor.chain().focus().undo().run(), disabled: !editor.can().undo() },
    { label: 'Redo', icon: Redo2, run: () => editor.chain().focus().redo().run(), disabled: !editor.can().redo() },
  ];

  return (
    <div className="rounded-card border border-line bg-surface-muted focus-within:border-line-strong transition overflow-hidden">
      <div role="toolbar" aria-label="Formatting" className="flex flex-wrap items-center gap-0.5 border-b border-line bg-surface px-2 py-1.5">
        {tools.map((tool, i) => tool === null ? (
          <span key={`sep-${i}`} className="mx-1 h-5 w-px bg-line" aria-hidden="true" />
        ) : (
          <button
            key={tool.label}
            type="button"
            title={tool.label}
            aria-label={tool.label}
            aria-pressed={tool.active === undefined ? undefined : tool.active}
            disabled={tool.disabled}
            // Keep the text selected while a button is pressed.
            onMouseDown={e => e.preventDefault()}
            onClick={tool.run}
            className={`h-8 w-8 inline-flex items-center justify-center rounded-control transition disabled:opacity-30 ${
              tool.active ? 'bg-accent-soft text-accent' : 'text-ink-muted hover:bg-surface-sunken hover:text-ink'
            }`}
          >
            <tool.icon className="h-4 w-4" />
          </button>
        ))}
      </div>
      <EditorContent editor={editor} />
    </div>
  );
}
