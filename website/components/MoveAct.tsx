"use client";

import { useEffect, useRef } from "react";
import { arcSections, arcSpaces, flightOrder } from "@/lib/site";
import { ArcPanel } from "./ArcPanel";
import { Favicon } from "./Icon";

const spaceIds = new Set(arcSpaces.map((s) => s.id));
const first = 0.08;
const gap = 0.11;
const length = 0.2;

const ease = (k: number) => 1 - Math.pow(1 - k, 3);
const clamp = (v: number) => Math.min(1, Math.max(0, v));

// Each item leaves the sample Arc sidebar in turn and flies to its row in Sela's
// sidebar: the fixed one on the left on wide screens, the panel below on phones.
// Progress is this act's own pinned travel, so jumping by link lands it right.
export function MoveAct() {
  const act = useRef<HTMLElement>(null);
  const flyers = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const section = act.current;
    const layer = flyers.current;
    if (!section || !layer) return;
    const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
    const phone = matchMedia("(max-width: 860px)");

    const setLanded = (id: string, landed: boolean) => {
      document
        .querySelectorAll<HTMLElement>(`[data-slot="${id}"], [data-log="${id}"]`)
        .forEach((el) => el.toggleAttribute("data-landed", landed));
      section
        .querySelector<HTMLElement>(`[data-arc-item="${id}"]`)
        ?.toggleAttribute("data-gone", landed);
    };

    if (reduce) {
      flightOrder.forEach((id) => setLanded(id, true));
      section.setAttribute("data-done", "");
      return;
    }

    const target = (id: string) => {
      const scope = phone.matches ? section : document.querySelector(".sidebar");
      return scope?.querySelector<HTMLElement>(`[data-slot="${id}"]`) ?? null;
    };

    let frame = 0;
    const tick = () => {
      frame = 0;
      const top = section.getBoundingClientRect().top;
      const travel = section.offsetHeight - window.innerHeight;
      const p = clamp(-top / Math.max(travel, 1));

      flightOrder.forEach((id, i) => {
        const k = clamp((p - (first + i * gap)) / length);
        const flyer = layer.querySelector<HTMLElement>(`[data-flyer="${id}"]`);
        const from = section.querySelector<HTMLElement>(`[data-arc-item="${id}"]`);
        const to = target(id);
        if (!flyer || !from || !to) return;

        if (k <= 0 || k >= 1) {
          flyer.style.opacity = "0";
          setLanded(id, k >= 1);
          if (k <= 0) from.removeAttribute("data-leaving");
          return;
        }
        setLanded(id, false);
        from.setAttribute("data-leaving", "");
        const a = from.getBoundingClientRect();
        const b = to.getBoundingClientRect();
        const e = ease(k);
        const scale = 1 + (b.height / a.height - 1) * e;
        const x = a.left + (b.left - a.left) * e;
        const y = a.top + (b.top - a.top) * e - Math.sin(Math.PI * k) * 56;
        flyer.style.width = `${a.width}px`;
        flyer.style.height = `${a.height}px`;
        flyer.style.transform = `translate3d(${x}px, ${y}px, 0) scale(${scale})`;
        flyer.style.opacity = "1";
      });

      const last = first + (flightOrder.length - 1) * gap + length;
      section.toggleAttribute("data-done", p >= last);
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
    <section id="the-move" ref={act} className="move" data-sc-act="pin" data-sc-span="3.8">
      <div data-sc-stage className="move__stage">
        <div className="move__copy">
          <h2 className="heading">Your sidebar moves in one go.</h2>
          <p className="body">
            On first launch Sela finds Arc on your Mac and offers to bring your sidebar across.
            Spaces, pinned tabs, folders and favourites keep their names and their order. The
            last 90 days of history come too, and Arc isn&rsquo;t changed.
          </p>
          <ol className="log" aria-label="Import log">
            <li className="log__line" data-landed="">Found Arc</li>
            {flightOrder.map((id) => (
              <li key={id} className="log__line" data-log={id}>
                {spaceIds.has(id) ? "Space" : "Pinned tab"}:{" "}
                {[...arcSpaces, ...arcSections].find((s) => s.id === id)?.title}
              </li>
            ))}
          </ol>
          <p className="move__done">
            <span className="move__wide">They&rsquo;re in the sidebar on the left now. Use them to get around.</span>
            <span className="move__narrow">They&rsquo;re in Sela now. Open the sidebar from the top bar to get around.</span>
          </p>
        </div>

        <div className="move__windows">
          <figure className="move__arc">
            <ArcPanel flight />
            <figcaption className="caption">
              A sample Arc sidebar. This page&rsquo;s own sections stand in for your tabs.
            </figcaption>
          </figure>

          <div className="move__sela" aria-hidden>
            <p className="move__sela-title">Sela</p>
            <ul className="arc__tabs">
              {arcSections.map((s) => (
                <li key={s.id} className="arc__tab slot" data-slot={s.id}>
                  <Favicon name={s.icon} tint={s.tint} />
                  <span>{s.title}</span>
                </li>
              ))}
            </ul>
            <div className="arc__spaces">
              {arcSpaces.map((s) => (
                <span key={s.id} className="space slot" data-slot={s.id} style={{ background: s.tint }} />
              ))}
            </div>
          </div>
        </div>
      </div>

      <div ref={flyers} className="flyers" aria-hidden>
        {arcSpaces.map((s) => (
          <span key={s.id} className="flyer space" data-flyer={s.id} style={{ background: s.tint }} />
        ))}
        {arcSections.map((s) => (
          <span key={s.id} className="flyer arc__tab" data-flyer={s.id}>
            <Favicon name={s.icon} tint={s.tint} />
            <span>{s.title}</span>
          </span>
        ))}
      </div>
    </section>
  );
}
