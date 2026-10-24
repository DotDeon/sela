"use client";

import { Archive, Columns2, Eye, Moon, X } from "lucide-react";
import { useEffect, useId, useRef, useState } from "react";

const paneNames = ["Notes", "Calendar", "Inbox", "Docs"];

function SplitDemo() {
  const [count, setCount] = useState(2);
  return (
    <div className="demo">
      <div className="split" data-count={count}>
        {paneNames.slice(0, count).map((name) => (
          <div key={name} className="split__pane">
            {name}
          </div>
        ))}
      </div>
      <div className="demo__controls">
        <button type="button" className="chip" disabled={count <= 1} onClick={() => setCount(count - 1)}>
          Fewer
        </button>
        <span className="demo__readout" aria-live="polite">
          {count} {count === 1 ? "tab" : "tabs"}
        </span>
        <button type="button" className="chip" disabled={count >= 4} onClick={() => setCount(count + 1)}>
          More
        </button>
      </div>
    </div>
  );
}

function PeekDemo() {
  const [open, setOpen] = useState(false);
  const close = useRef<HTMLButtonElement>(null);
  const opener = useRef<HTMLButtonElement>(null);
  const titleId = useId();

  useEffect(() => {
    if (!open) return;
    close.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setOpen(false);
        opener.current?.focus();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <div className="demo peek">
      <div className="peek__page">
        <p className="peek__from">Pinned tab: Team notes</p>
        <p>
          Plan for Thursday is in the{" "}
          <button ref={opener} type="button" className="peek__link" onClick={() => setOpen(true)}>
            shared doc
          </button>
          , and the venue details are below.
        </p>
      </div>
      {open && (
        <div className="peek__sheet" role="dialog" aria-modal="false" aria-labelledby={titleId}>
          <div className="peek__bar">
            <p id={titleId}>Peek: shared doc</p>
            <button
              ref={close}
              type="button"
              className="icon-button"
              aria-label="Close Peek"
              onClick={() => {
                setOpen(false);
                opener.current?.focus();
              }}
            >
              <X size={14} aria-hidden />
            </button>
          </div>
          <p className="peek__body">Thursday: 10:00 stand-up, 14:00 review.</p>
        </div>
      )}
    </div>
  );
}

const sleepTabs = [
  { name: "Recipes", seen: 2 },
  { name: "Flights", seen: 6 },
  { name: "Forum thread", seen: 11 },
  { name: "Long read", seen: 14 },
];

function SleepDemo() {
  const [later, setLater] = useState(0);
  const id = useId();
  return (
    <div className="demo">
      <ul className="rows">
        {sleepTabs.map((t) => {
          const minutes = t.seen + later;
          const asleep = minutes >= 15;
          return (
            <li key={t.name} className="row" data-asleep={asleep || undefined}>
              <span>{t.name}</span>
              <span className="row__meta">
                {asleep ? (
                  <>
                    <Moon size={12} aria-hidden /> Asleep
                  </>
                ) : (
                  `${minutes} min ago`
                )}
              </span>
            </li>
          );
        })}
      </ul>
      <label className="slider" htmlFor={id}>
        <span>Time away: {later} min</span>
        <input id={id} type="range" min={0} max={15} value={later} onChange={(e) => setLater(Number(e.target.value))} />
      </label>
    </div>
  );
}

const archiveTabs = [
  { name: "Search results", age: 1 },
  { name: "Weather", age: 4 },
  { name: "Shop checkout", age: 8 },
  { name: "Old article", age: 11 },
];

function ArchiveDemo() {
  const [later, setLater] = useState(0);
  const id = useId();
  const open = archiveTabs.filter((t) => t.age + later < 12);
  const archived = archiveTabs.filter((t) => t.age + later >= 12);
  return (
    <div className="demo">
      <ul className="rows">
        {open.map((t) => (
          <li key={t.name} className="row">
            <span>{t.name}</span>
            <span className="row__meta">{t.age + later} h</span>
          </li>
        ))}
        {open.length === 0 && <li className="row row--empty">No unpinned tabs</li>}
      </ul>
      <p className="rows__label">
        <Archive size={12} aria-hidden /> Archived: {archived.length}
      </p>
      <label className="slider" htmlFor={id}>
        <span>Hours later: {later}</span>
        <input id={id} type="range" min={0} max={12} value={later} onChange={(e) => setLater(Number(e.target.value))} />
      </label>
    </div>
  );
}

export function EveryDay() {
  return (
    <section id="every-day" className="everyday" data-sc-act="pan" data-sc-span="3">
      <div data-sc-stage className="everyday__stage">
        <div className="rail" data-sc-pan="0.04">
          <div className="rail__lead">
            <h2 className="heading">It works the way your hands already do.</h2>
            <p className="body">
              Cmd+T opens the command bar. Cmd+F finds text on the page. Two fingers swipe
              between spaces. Try the four on the right.
            </p>
          </div>

          <article className="card">
            <h3 className="card__title">
              <Columns2 size={15} aria-hidden /> Split view
            </h3>
            <p className="card__text">Up to four tabs side by side.</p>
            <SplitDemo />
          </article>

          <article className="card">
            <h3 className="card__title">
              <Eye size={15} aria-hidden /> Peek
            </h3>
            <p className="card__text">
              Links from pinned tabs and favourites open over the page. Close it and you&rsquo;re
              where you were.
            </p>
            <PeekDemo />
          </article>

          <article className="card">
            <h3 className="card__title">
              <Moon size={15} aria-hidden /> Tab sleep
            </h3>
            <p className="card__text">
              Tabs you haven&rsquo;t looked at for 15 minutes sleep to save memory, and wake
              where you left them.
            </p>
            <SleepDemo />
          </article>

          <article className="card">
            <h3 className="card__title">
              <Archive size={15} aria-hidden /> Archive
            </h3>
            <p className="card__text">
              Unpinned tabs archive themselves after 12 hours, and stay findable for 30 days.
            </p>
            <ArchiveDemo />
          </article>

          <div className="rail__note">
            <p className="body">
              Also: downloads, file uploads, and a prompt before any site uses your camera or
              microphone.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
