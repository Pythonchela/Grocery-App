'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

/**
 * Voice in and out via the browser's own Web Speech API.
 *
 * Deliberately not a cloud speech service: this needs no second API key, no
 * audio upload, and no per-minute cost, and the recognition runs against the
 * language the shopper actually picked. The tradeoff is uneven support —
 * recognition is Chrome/Edge/Safari, and the Indian-language voices available
 * for playback depend on what the OS has installed. Everything below reports
 * what is actually supported rather than assuming, so the UI can hide controls
 * that would do nothing.
 */

export const VOICE_LANGUAGES = [
  { code: 'en-IN', label: 'English' },
  { code: 'hi-IN', label: 'हिन्दी' },
  { code: 'bn-IN', label: 'বাংলা' },
  { code: 'ta-IN', label: 'தமிழ்' },
  { code: 'te-IN', label: 'తెలుగు' },
  { code: 'mr-IN', label: 'मराठी' },
  { code: 'gu-IN', label: 'ગુજરાતી' },
  { code: 'kn-IN', label: 'ಕನ್ನಡ' },
];

export function useVoice({ lang = 'en-IN', onResult } = {}) {
  const [listening, setListening] = useState(false);
  const [speaking, setSpeaking] = useState(false);
  const [error, setError] = useState(null);
  const [supported, setSupported] = useState({ listen: false, speak: false });

  const recognitionRef = useRef(null);
  // Kept in a ref so a re-render mid-utterance doesn't leave the recognition
  // instance calling a stale handler.
  const onResultRef = useRef(onResult);
  onResultRef.current = onResult;

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    setSupported({
      listen: Boolean(SpeechRecognition),
      speak: typeof window.speechSynthesis !== 'undefined',
    });
  }, []);

  const stopListening = useCallback(() => {
    recognitionRef.current?.stop();
    recognitionRef.current = null;
    setListening(false);
  }, []);

  const startListening = useCallback(() => {
    if (typeof window === 'undefined') return;
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
      setError('This browser cannot listen — try Chrome, Edge or Safari.');
      return;
    }

    // A second start() on a live instance throws; restart cleanly instead.
    recognitionRef.current?.stop();
    setError(null);

    const recognition = new SpeechRecognition();
    recognition.lang = lang;
    recognition.continuous = false;
    recognition.interimResults = false;
    recognition.maxAlternatives = 1;

    recognition.onresult = (event) => {
      const transcript = event.results?.[0]?.[0]?.transcript?.trim();
      if (transcript) onResultRef.current?.(transcript);
    };
    recognition.onerror = (event) => {
      setError(
        event.error === 'not-allowed'
          ? 'Microphone access was blocked.'
          : event.error === 'no-speech'
            ? "Didn't catch that — try again."
            : 'Voice input failed.'
      );
      setListening(false);
    };
    recognition.onend = () => setListening(false);

    recognitionRef.current = recognition;
    try {
      recognition.start();
      setListening(true);
    } catch {
      setError('Could not start the microphone.');
      setListening(false);
    }
  }, [lang]);

  const speak = useCallback(
    (text) => {
      if (typeof window === 'undefined' || !window.speechSynthesis || !text) return;
      window.speechSynthesis.cancel();

      const utterance = new SpeechSynthesisUtterance(text);
      utterance.lang = lang;

      // Prefer a voice actually installed for this language; browsers otherwise
      // read Hindi text with an English voice, which is unintelligible.
      const voices = window.speechSynthesis.getVoices();
      const match =
        voices.find((v) => v.lang === lang) ||
        voices.find((v) => v.lang?.startsWith(lang.split('-')[0]));
      if (match) utterance.voice = match;

      utterance.onstart = () => setSpeaking(true);
      utterance.onend = () => setSpeaking(false);
      utterance.onerror = () => setSpeaking(false);

      window.speechSynthesis.speak(utterance);
    },
    [lang]
  );

  const stopSpeaking = useCallback(() => {
    if (typeof window === 'undefined' || !window.speechSynthesis) return;
    window.speechSynthesis.cancel();
    setSpeaking(false);
  }, []);

  // Leaving the page mid-utterance otherwise keeps the browser talking.
  useEffect(
    () => () => {
      recognitionRef.current?.stop();
      if (typeof window !== 'undefined') window.speechSynthesis?.cancel();
    },
    []
  );

  return { listening, speaking, error, supported, startListening, stopListening, speak, stopSpeaking };
}
