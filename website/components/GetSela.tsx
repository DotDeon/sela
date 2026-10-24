"use client";

import { Bug, CodeXml, CornerDownLeft, Download, Heart, Search } from "lucide-react";
import { useId, useMemo, useState } from "react";
import { downloadLabel, links } from "@/lib/site";

const commands = [
  { label: downloadLabel, detail: "macOS 15 or later. Free.", href: links.download, Glyph: Download, words: "download get install mac app" },
  { label: "Sponsor on GitHub", detail: "Sponsors pay for the work.", href: links.sponsor, Glyph: Heart, words: "sponsor donate support money" },
  { label: "Read the code", detail: "GPL-3.0, on GitHub.", href: links.code, Glyph: CodeXml, words: "code source github repo open" },
  { label: "Report a problem", detail: "Open an issue.", href: links.issues, Glyph: Bug, words: "report bug issue problem help" },
];

// The close is Sela's own command bar. It filters as you type, arrows move the
// highlight and Return opens it. Without JavaScript the rows are plain links.
export function GetSela() {
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const listId = useId();

  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return commands;
    return commands.filter((c) => `${c.label} ${c.words}`.toLowerCase().includes(q));
  }, [query]);
  const selected = Math.min(active, Math.max(matches.length - 1, 0));

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
    }
  };

  return (
    <section id="get-sela" className="close" data-sc-act="pin" data-sc-span="1.2">
      <div data-sc-stage className="close__stage">
        <picture>
          <source media="(max-width: 860px)" srcSet="/media/close-m.jpg" />
          <img className="close__ground" src="/media/close.jpg" alt="" />
        </picture>
        <div className="close__scrim" aria-hidden />
        <div className="close__inner">
          <h2 className="heading" data-sc-cue="0.02">
            Get Sela
          </h2>
          <p className="body close__lede" data-sc-cue="0.04">
            Free, and it stays free. Sponsors pay for the work.
          </p>

          <div className="command" data-sc-cue="0.06" data-sc-rise="0">
            <label className="command__field">
              <Search size={16} aria-hidden />
              <input
                type="text"
                role="combobox"
                aria-expanded="true"
                aria-controls={listId}
                aria-activedescendant={matches[selected] ? `${listId}-${selected}` : undefined}
                aria-label="Command bar"
                placeholder="Type a command, or press Return"
                autoComplete="off"
                spellCheck={false}
                value={query}
                onChange={(e) => {
                  setQuery(e.target.value);
                  setActive(0);
                }}
                onKeyDown={onKey}
              />
            </label>
            <ul id={listId} role="listbox" className="command__list" aria-label="Commands">
              {matches.map((c, i) => (
                <li key={c.href} id={`${listId}-${i}`} role="option" aria-selected={i === selected}>
                  <a
                    href={c.href}
                    className="command__row"
                    data-active={i === selected || undefined}
                    onMouseEnter={() => setActive(i)}
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
        </div>

        <footer className="foot">
          <p>Sela is free software under the GNU GPL, version 3.</p>
        </footer>
      </div>
    </section>
  );
}
