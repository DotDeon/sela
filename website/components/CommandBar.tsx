"use client";

import { Bug, CodeXml, CornerDownLeft, Download, Heart, Search } from "lucide-react";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import { downloadLabel, links } from "@/lib/site";

const commands = [
  { label: downloadLabel, detail: "macOS 15 or later. Free.", href: links.download, Glyph: Download, words: "download get install mac app" },
  { label: "Sponsor on GitHub", detail: "Sponsors pay for the work.", href: links.sponsor, Glyph: Heart, words: "sponsor donate support money" },
  { label: "Read the code", detail: "GPL-3.0, on GitHub.", href: links.code, Glyph: CodeXml, words: "code source github repo open" },
  { label: "Report a problem", detail: "Open an issue.", href: links.issues, Glyph: Bug, words: "report bug issue problem help" },
];

// Sela's own command bar. It filters as you type, arrows move the highlight
// and Return opens it. Without JavaScript the rows are plain links.
//
// Docked, it sits at the foot of the sidebar on every screen: the list stays
// closed until the field has focus, opens upward, and Command-K focuses it.
export function CommandBar({ docked = false }: { docked?: boolean }) {
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const [focused, setFocused] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  const listId = useId();
  const open = !docked || focused;

  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return commands;
    return commands.filter((c) => `${c.label} ${c.words}`.toLowerCase().includes(q));
  }, [query]);
  const selected = Math.min(active, Math.max(matches.length - 1, 0));

  useEffect(() => {
    if (!docked) return;
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        input.current?.focus();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [docked]);

  const onKey = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((selected + 1) % Math.max(matches.length, 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((selected - 1 + matches.length) % Math.max(matches.length, 1));
    } else if (e.key === "Enter" && matches[selected]) {
      e.preventDefault();
      window.location.href = matches[selected].href;
    } else if (e.key === "Escape" && docked) {
      setQuery("");
      input.current?.blur();
    }
  };

  return (
    <div className={docked ? "command command--docked" : "command"} data-open={open || undefined}>
      <label className="command__field">
        <Search size={docked ? 14 : 16} aria-hidden />
        <input
          ref={input}
          type="text"
          role="combobox"
          aria-expanded={open}
          aria-controls={listId}
          aria-activedescendant={open && matches[selected] ? `${listId}-${selected}` : undefined}
          aria-label="Command bar"
          placeholder={docked ? "Get Sela" : "Type a command, or press Return"}
          autoComplete="off"
          spellCheck={false}
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setActive(0);
          }}
          onKeyDown={onKey}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
        />
        {docked && !focused && (
          <kbd className="command__key" aria-hidden>
            ⌘K
          </kbd>
        )}
      </label>
      <ul id={listId} role="listbox" className="command__list" aria-label="Commands" hidden={!open}>
        {matches.map((c, i) => (
          <li key={c.href} id={`${listId}-${i}`} role="option" aria-selected={i === selected}>
            <a
              href={c.href}
              className="command__row"
              data-active={i === selected || undefined}
              onMouseEnter={() => setActive(i)}
              onMouseDown={(e) => e.preventDefault()}
              tabIndex={-1}
            >
              <c.Glyph size={16} aria-hidden />
              <span className="command__label">{c.label}</span>
              <span className="command__detail">{c.detail}</span>
              {i === selected && <CornerDownLeft size={14} aria-hidden className="command__enter" />}
            </a>
          </li>
        ))}
        {matches.length === 0 && (
          <li className="command__empty" role="option" aria-selected="false">
            Nothing matches &ldquo;{query}&rdquo;. Try &ldquo;download&rdquo;.
          </li>
        )}
      </ul>
    </div>
  );
}
