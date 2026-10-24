"use client";

import { Bug, CodeXml, Download, Heart, PanelLeft, X } from "lucide-react";
import { useEffect, useState } from "react";
import { downloadLabel, links, sections } from "@/lib/site";
import { CommandBar } from "./CommandBar";
import { Favicon } from "./Icon";

const favourites = [
  { href: links.download, label: downloadLabel, Glyph: Download },
  { href: links.sponsor, label: "Sponsor on GitHub", Glyph: Heart },
  { href: links.code, label: "Read the code", Glyph: CodeXml },
  { href: links.issues, label: "Report a problem", Glyph: Bug },
];

// The page's navigation is a browser sidebar: favourites, pinned tabs for the
// sections, the command bar docked at the foot, and a space bar. Rows for sections that climb out of the river
// carry data-slot so the flight can find them and mark them landed.
export function Chrome() {
  const [current, setCurrent] = useState(sections[0].id);
  const [host, setHost] = useState("sela");
  const [open, setOpen] = useState(false);

  useEffect(() => {
    setHost(window.location.host || "sela");
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) setCurrent(entry.target.id);
        }
      },
      { rootMargin: "-45% 0px -54% 0px" },
    );
    for (const s of sections) {
      const el = document.getElementById(s.id);
      if (el) observer.observe(el);
    }
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  const currentTitle = sections.find((s) => s.id === current)?.title ?? "Sela";

  return (
    <>
      <header className="toolbar">
        <button
          type="button"
          className="toolbar__button"
          aria-label="Show sidebar"
          aria-expanded={open}
          aria-controls="sidebar"
          onClick={() => setOpen(true)}
        >
          <PanelLeft size={18} aria-hidden />
        </button>
        <p className="toolbar__address">
          <span className="address__host">{host}</span>
          <span className="address__path"> / {currentTitle}</span>
        </p>
      </header>

      <div className="scrim-drawer" data-open={open} onClick={() => setOpen(false)} aria-hidden />

      <aside id="sidebar" className="sidebar" data-open={open} aria-label="Sidebar">
        <div className="sidebar__top">
          <span className="lights" aria-hidden>
            <i /> <i /> <i />
          </span>
          <button
            type="button"
            className="sidebar__close"
            aria-label="Hide sidebar"
            onClick={() => setOpen(false)}
          >
            <X size={16} aria-hidden />
          </button>
        </div>

        <p className="address" aria-label="Address">
          <span className="address__host">{host}</span>
          <span className="address__path">/#{current}</span>
        </p>

        <nav aria-label="Page">
          <ul className="favourites">
            {favourites.map(({ href, label, Glyph }) => (
              <li key={href}>
                <a href={href} className="favourite" aria-label={label} title={label}>
                  <Glyph size={16} strokeWidth={2} aria-hidden />
                </a>
              </li>
            ))}
          </ul>

          <ul className="tabs">
            {sections.map((s) => (
              <li key={s.id}>
                <a
                  href={`#${s.id}`}
                  className={s.drifts ? "tab slot" : "tab"}
                  data-slot={s.drifts ? s.id : undefined}
                  aria-current={current === s.id ? "location" : undefined}
                  onClick={() => setOpen(false)}
                >
                  <Favicon name={s.icon} tint={s.tint} />
                  <span>{s.title}</span>
                </a>
              </li>
            ))}
          </ul>
        </nav>

        <div className="sidebar__command">
          <CommandBar docked />
        </div>

        <div className="spacebar" aria-label="Spaces">
          <span className="space space--current" title="Sela" />
        </div>
      </aside>
    </>
  );
}
