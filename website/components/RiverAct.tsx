"use client";

import { Globe } from "lucide-react";
import { useEffect, useRef } from "react";
import { looseTabs, pinnedTabs } from "@/lib/site";
import { Favicon } from "./Icon";

// Where each tab floats on the water, as fractions of the stage.
const pinnedAt = [
  [0.34, 0.16],
  [0.56, 0.3],
  [0.44, 0.47],
  [0.68, 0.57],
];
const looseAt = [
  [0.75, 0.11],
  [0.2, 0.26],
  [0.82, 0.38],
  [0.6, 0.74],
];

const first = 0.22;
const gap = 0.1;
const length = 0.18;
const ease = (k: number) => 1 - Math.pow(1 - k, 3);
const clamp = (v: number) => Math.min(1, Math.max(0, v));

// The river is a scrubbed clip of water running top-left to bottom-right. Tabs
// float on it and drift with the scroll. Pinned ones climb out, one at a time,
// into their rows in the sidebar, where they stay and work as navigation.
// Unpinned ones are carried off downstream and fade, the way they archive.
export function RiverAct() {
  const act = useRef<HTMLElement>(null);
  const layer = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const section = act.current;
    const chips = layer.current;
    if (!section || !chips) return;
    const stage = section.querySelector<HTMLElement>("[data-sc-stage]");
    if (!stage) return;
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
    const phone = matchMedia("(max-width: 860px)");

    const setLanded = (id: string, landed: boolean) =>
      document
        .querySelectorAll<HTMLElement>(`[data-slot="${id}"]`)
        .forEach((el) => el.toggleAttribute("data-landed", landed));

    if (reduce) {
      pinnedTabs.forEach((t) => setLanded(t.id, true));
      chips.hidden = true;
      return;
    }

    const target = (id: string) => {
      const scope = phone.matches ? section : document.querySelector(".sidebar");
      return scope?.querySelector<HTMLElement>(`[data-slot="${id}"]`) ?? null;
    };

    let frame = 0;
    const tick = () => {
      frame = 0;
      const box = stage.getBoundingClientRect();
      const travel = section.offsetHeight - window.innerHeight;
      const p = clamp(-section.getBoundingClientRect().top / Math.max(travel, 1));
      const visible = box.bottom > 0 && box.top < window.innerHeight;
      chips.style.visibility = visible ? "visible" : "hidden";
      chips.style.clipPath = `inset(${Math.max(box.top, 0)}px 0 ${Math.max(window.innerHeight - box.bottom, 0)}px 0)`;
      if (!visible) return;

      const drift = Math.min(window.innerWidth, 1400) * 0.1 * p;
      const place = (el: HTMLElement, fx: number, fy: number) => ({
        x: box.left + fx * box.width - el.offsetWidth / 2 + drift * 0.8,
        y: box.top + fy * box.height + drift * 0.6,
      });

      pinnedTabs.forEach((tab, i) => {
        const el = chips.querySelector<HTMLElement>(`[data-chip="${tab.id}"]`);
        const to = target(tab.id);
        if (!el || !to) return;
        const from = place(el, pinnedAt[i][0], pinnedAt[i][1]);
        const k = clamp((p - (first + i * gap)) / length);
        if (k >= 1) {
          el.style.opacity = "0";
          setLanded(tab.id, true);
          return;
        }
        setLanded(tab.id, false);
        const b = to.getBoundingClientRect();
        const e = ease(k);
        const x = from.x + (b.left - from.x) * e;
        const y = from.y + (b.top - from.y) * e - Math.sin(Math.PI * k) * 60;
        const scale = 1 + (b.height / el.offsetHeight - 1) * e;
        el.style.opacity = "1";
        el.style.transform = `translate3d(${x}px, ${y}px, 0) scale(${scale})`;
        el.toggleAttribute("data-lifting", k > 0);
      });

      looseTabs.forEach((_, i) => {
        const el = chips.querySelector<HTMLElement>(`[data-chip="loose-${i}"]`);
        if (!el) return;
        const from = place(el, looseAt[i][0], looseAt[i][1]);
        const away = clamp((p - 0.42 - i * 0.04) / 0.3);
        const extra = away * away * 260;
        el.style.opacity = String(1 - away);
        el.style.transform = `translate3d(${from.x + extra * 0.8}px, ${from.y + extra * 0.6}px, 0)`;
      });
    };

    const schedule = () => {
      if (!frame) frame = requestAnimationFrame(tick);
    };
    tick();
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
    };
  }, []);

  return (
    <section
      id="river"
      ref={act}
      className="river"
      data-sc-act="scrub"
      data-sc-span="3.6"
      data-sc-dwell="0.2"
    >
      <div data-sc-stage>
        <picture>
          <source media="(max-width: 860px)" srcSet="/media/river-poster-m.jpg" />
          <img className="sc-stage__poster" src="/media/river-poster.jpg" alt="" />
        </picture>
        <video
          data-sc-scrub
          data-sc-src="/media/river.mp4"
          data-sc-src-mobile="/media/river-m.mp4"
          muted
          playsInline
        />
        <div className="sc-scrim river__scrim" aria-hidden />

        <div className="river__copy" data-sc-cue="0.02 0.5 0.06 0.06">
          <h2 className="heading">Pin a tab and it stays.</h2>
          <p className="body">
            Pinned tabs and folders keep their place in the sidebar, in the order you left them,
            in each of your spaces.
          </p>
        </div>
        <div className="river__copy" data-sc-cue="0.56 1 0.06 0.04">
          <h2 className="heading">The rest drift away.</h2>
          <p className="body">
            Unpinned tabs archive themselves after 12 hours, and you can find them again for 30
            days.
          </p>
        </div>

        <div className="river__dock" aria-hidden>
          {pinnedTabs.map((t) => (
            <span key={t.id} className="chip-tab slot" data-slot={t.id}>
              <Favicon name={t.icon} tint={t.tint} />
              <span>{t.title}</span>
            </span>
          ))}
        </div>
      </div>

      <div ref={layer} className="drift" aria-hidden>
        {pinnedTabs.map((t) => (
          <span key={t.id} className="chip-tab chip-tab--pinned" data-chip={t.id}>
            <Favicon name={t.icon} tint={t.tint} />
            <span>{t.title}</span>
          </span>
        ))}
        {looseTabs.map((title, i) => (
          <span key={title} className="chip-tab chip-tab--loose" data-chip={`loose-${i}`}>
            <span className="favicon favicon--plain">
              <Globe size={11} strokeWidth={2.2} aria-hidden />
            </span>
            <span>{title}</span>
          </span>
        ))}
      </div>
    </section>
  );
}
