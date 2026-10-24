'use client';

import React, { useEffect, useRef, useState } from 'react';
import { Bot, X, Send, ShoppingBag, Mic, MicOff, Volume2, VolumeX, AlertCircle } from 'lucide-react';
import { useVoice, VOICE_LANGUAGES } from '../lib/ai/useVoice';

const GREETING = {
  id: 'greeting',
  sender: 'agent',
  text: "Hi! Tell me what you're shopping for — what it's for, roughly what you want to spend — and I'll narrow it down to a few options.",
  products: [],
};

export default function AIAgentCopilot({ onAddToCart }) {
  const [isOpen, setIsOpen] = useState(false);
  const [messages, setMessages] = useState([GREETING]);
  const [inputMsg, setInputMsg] = useState('');
  const [isThinking, setIsThinking] = useState(false);
  const [error, setError] = useState(null);
  const [lang, setLang] = useState('en-IN');
  const [speakReplies, setSpeakReplies] = useState(false);

  const scrollRef = useRef(null);
  // Read inside the async send so a reply can't be spoken with a stale setting.
  const speakRepliesRef = useRef(speakReplies);
  speakRepliesRef.current = speakReplies;

  const { listening, speaking, error: voiceError, supported, startListening, stopListening, speak, stopSpeaking } =
    useVoice({ lang, onResult: (transcript) => handleSend(transcript) });

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' });
  }, [messages, isThinking]);

  const handleSend = async (textToSend = inputMsg) => {
    const text = textToSend.trim();
    if (!text || isThinking) return;

    stopSpeaking();
    setError(null);
    setInputMsg('');

    const nextMessages = [...messages, { id: `u${Date.now()}`, sender: 'user', text }];
    setMessages(nextMessages);
    setIsThinking(true);

    try {
      // The greeting is UI-only — the model never sent it, so it stays out of
      // the history rather than being replayed back as its own words.
      const history = nextMessages
        .filter((m) => m.id !== 'greeting')
        .map((m) => ({ role: m.sender === 'user' ? 'user' : 'assistant', content: m.text }));

      const res = await fetch('/api/ai/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messages: history }),
      });
      const data = await res.json();

      if (!res.ok) {
        setError(data?.error || 'The assistant is unavailable right now.');
        return;
      }

      setMessages((prev) => [
        ...prev,
        { id: `a${Date.now()}`, sender: 'agent', text: data.reply, products: data.products || [] },
      ]);
      if (speakRepliesRef.current) speak(data.reply);
    } catch {
      setError('Could not reach the assistant. Check your connection and try again.');
    } finally {
      setIsThinking(false);
    }
  };

  return (
    <>
      {!isOpen && (
        <button
          onClick={() => setIsOpen(true)}
          className="fixed bottom-6 left-6 z-40 flex items-center gap-3 rounded-pill border border-line bg-surface px-4 py-3 shadow-raised transition hover:border-accent"
        >
          <Bot className="h-5 w-5 text-accent" />
          <span className="hidden text-xs font-black uppercase tracking-wider text-ink sm:block">
            Shopping Assistant
          </span>
        </button>
      )}

      {isOpen && (
        <div className="fixed bottom-6 left-6 z-50 flex h-[560px] w-96 max-w-[calc(100vw-2rem)] flex-col overflow-hidden rounded-panel border border-line bg-surface shadow-raised sm:w-[420px]">
          <div className="flex items-center justify-between border-b border-line bg-surface-muted p-4">
            <div className="flex items-center gap-2.5">
              <div className="grid h-9 w-9 place-items-center rounded-card border border-line bg-surface">
                <Bot className="h-5 w-5 text-accent" />
              </div>
              <div>
                <h4 className="text-xs font-black text-ink">Shopping Assistant</h4>
                <span className="text-[10px] text-ink-subtle">Asks first, then finds</span>
              </div>
            </div>
            <button
              onClick={() => {
                stopSpeaking();
                stopListening();
                setIsOpen(false);
              }}
              className="grid h-8 w-8 place-items-center rounded-control text-ink-subtle transition hover:bg-surface-sunken hover:text-ink"
              aria-label="Close assistant"
            >
              <X className="h-5 w-5" />
            </button>
          </div>

          <div ref={scrollRef} className="flex-1 space-y-4 overflow-y-auto p-4 text-xs">
            {messages.map((m) => (
              <div key={m.id} className={`flex flex-col gap-2 ${m.sender === 'user' ? 'items-end' : 'items-start'}`}>
                <div
                  className={`max-w-[90%] whitespace-pre-wrap rounded-card px-3.5 py-3 leading-relaxed ${
                    m.sender === 'user'
                      ? 'bg-accent font-semibold text-on-accent'
                      : 'border border-line bg-surface-muted text-ink'
                  }`}
                >
                  {m.text}
                </div>

                {m.products?.length > 0 && (
                  <div className="w-full space-y-2 pt-1">
                    {m.products.map((p) => (
                      <div
                        key={p.id}
                        className="flex items-center gap-3 rounded-card border border-line bg-surface p-2.5"
                      >
                        {p.image && (
                          <img
                            src={p.image}
                            alt={p.title}
                            className="h-12 w-12 shrink-0 rounded-control border border-line object-cover"
                          />
                        )}
                        <div className="min-w-0 flex-1">
                          <a
                            href={`/product/${p.slug}`}
                            className="block truncate text-[11px] font-bold text-ink hover:text-accent"
                          >
                            {p.title}
                          </a>
                          <div className="mt-0.5 flex items-center gap-2">
                            <span className="text-xs font-black text-accent">
                              ₹{Number(p.price).toLocaleString('en-IN')}
                            </span>
                            {p.rating != null && (
                              <span className="text-[10px] font-bold text-ink-subtle">★ {p.rating}</span>
                            )}
                          </div>
                        </div>
                        {onAddToCart && (
                          <button
                            onClick={() => onAddToCart(p)}
                            className="grid h-8 w-8 shrink-0 place-items-center rounded-control bg-accent text-on-accent transition hover:opacity-90"
                            aria-label={`Add ${p.title} to cart`}
                          >
                            <ShoppingBag className="h-3.5 w-3.5" />
                          </button>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ))}

            {isThinking && (
              <div className="flex w-fit items-center gap-2 rounded-card border border-line bg-surface-muted px-3 py-2 text-[10px] text-ink-subtle">
                <Bot className="h-3.5 w-3.5 animate-pulse text-accent" />
                <span>Looking through the catalog…</span>
              </div>
            )}

            {(error || voiceError) && (
              <div className="flex items-start gap-2 rounded-card border border-danger/30 bg-danger/5 p-3 text-[11px] font-semibold text-danger">
                <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                <span>{error || voiceError}</span>
              </div>
            )}
          </div>

          <div className="flex items-center gap-2 border-t border-line bg-surface-muted px-3 py-2">
            <select
              value={lang}
              onChange={(e) => setLang(e.target.value)}
              className="rounded-control border border-line bg-surface px-2 py-1 text-[10px] font-bold text-ink outline-none"
              aria-label="Voice language"
            >
              {VOICE_LANGUAGES.map((l) => (
                <option key={l.code} value={l.code}>
                  {l.label}
                </option>
              ))}
            </select>

            {supported.speak && (
              <button
                onClick={() => {
                  if (speaking) stopSpeaking();
                  setSpeakReplies((v) => !v);
                }}
                className={`flex items-center gap-1 rounded-control border px-2 py-1 text-[10px] font-bold transition ${
                  speakReplies ? 'border-accent bg-accent/10 text-accent' : 'border-line bg-surface text-ink-subtle'
                }`}
                title={speakReplies ? 'Replies are read aloud' : 'Read replies aloud'}
              >
                {speakReplies ? <Volume2 className="h-3 w-3" /> : <VolumeX className="h-3 w-3" />}
                {speaking ? 'Speaking' : 'Speak'}
              </button>
            )}
          </div>

          <form
            onSubmit={(e) => {
              e.preventDefault();
              handleSend();
            }}
            className="flex items-center gap-2 border-t border-line bg-surface p-3"
          >
            {supported.listen && (
              <button
                type="button"
                onClick={listening ? stopListening : startListening}
                className={`grid h-9 w-9 shrink-0 place-items-center rounded-pill border transition ${
                  listening
                    ? 'animate-pulse border-danger bg-danger/10 text-danger'
                    : 'border-line bg-surface text-ink-subtle hover:text-accent'
                }`}
                aria-label={listening ? 'Stop listening' : 'Speak your question'}
              >
                {listening ? <MicOff className="h-4 w-4" /> : <Mic className="h-4 w-4" />}
              </button>
            )}
            <input
              type="text"
              placeholder={listening ? 'Listening…' : 'What are you looking for?'}
              value={inputMsg}
              onChange={(e) => setInputMsg(e.target.value)}
              disabled={isThinking}
              className="flex-1 rounded-pill border border-line bg-surface px-3.5 py-2 text-xs font-semibold text-ink outline-none placeholder:text-ink-subtle focus:border-accent disabled:opacity-60"
            />
            <button
              type="submit"
              disabled={isThinking || !inputMsg.trim()}
              className="grid h-9 w-9 shrink-0 place-items-center rounded-pill bg-accent text-on-accent transition hover:opacity-90 disabled:opacity-40"
              aria-label="Send"
            >
              <Send className="h-4 w-4" />
            </button>
          </form>
        </div>
      )}
    </>
  );
}
