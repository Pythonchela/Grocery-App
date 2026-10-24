"use client";

import { useTheme } from "next-themes";
import { useEffect, useState } from "react";
import { Moon, Sun, Monitor } from "lucide-react";

export const THEME_OPTIONS = [
  { value: "light", label: "Light", Icon: Sun },
  { value: "dark", label: "Dark", Icon: Moon },
  { value: "system", label: "System", Icon: Monitor },
];

/**
 * Navbar control: one tap cycles Light → Dark → System. The icon shows the
 * *chosen* mode (not the resolved one), so "System" is visible as its own
 * state instead of masquerading as whichever theme the OS happens to be in.
 */
export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted) return <div className="w-9 h-9"></div>;

  const index = Math.max(0, THEME_OPTIONS.findIndex((o) => o.value === theme));
  const current = THEME_OPTIONS[index];
  const next = THEME_OPTIONS[(index + 1) % THEME_OPTIONS.length];

  return (
    <button
      onClick={() => setTheme(next.value)}
      className="p-2 rounded-pill hover:bg-surface-sunken transition-colors"
      aria-label={`Theme: ${current.label}. Switch to ${next.label}`}
      title={`Theme: ${current.label}`}
    >
      <current.Icon size={20} className="text-ink-muted" />
    </button>
  );
}

/** Segmented Light / Dark / System picker for settings pages. */
export function ThemePicker() {
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  const active = mounted ? theme : null;

  return (
    <div role="radiogroup" aria-label="Theme" className="grid grid-cols-3 gap-2">
      {THEME_OPTIONS.map(({ value, label, Icon }) => {
        const selected = active === value;
        return (
          <button
            key={value}
            type="button"
            role="radio"
            aria-checked={selected}
            onClick={() => setTheme(value)}
            className={`flex flex-col items-center gap-1.5 rounded-card border px-3 py-3 text-xs font-bold transition ${
              selected
                ? "border-accent bg-accent-soft text-ink"
                : "border-line bg-surface text-ink-muted hover:bg-surface-muted"
            }`}
          >
            <Icon size={18} />
            {label}
          </button>
        );
      })}
    </div>
  );
}
