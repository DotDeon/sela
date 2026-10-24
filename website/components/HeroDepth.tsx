"use client";

import { useEffect } from "react";

// On a fine pointer, the hero's planes lean a little toward the cursor. The
// values feed the same transforms the scroll drives, so neither fights the
// other. Touch, keyboard and reduced motion keep the still composition.
export function HeroDepth() {
  useEffect(() => {
    const hero = document.getElementById("sela");
    const fine = matchMedia("(hover: hover) and (pointer: fine)");
    const reduce = matchMedia("(prefers-reduced-motion: reduce)");
    if (!hero || !fine.matches || reduce.matches) return;
    let frame = 0;
    let x = 0;
    let y = 0;
    const onMove = (e: PointerEvent) => {
      x = e.clientX / window.innerWidth - 0.5;
      y = e.clientY / window.innerHeight - 0.5;
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        hero.style.setProperty("--mx", x.toFixed(3));
        hero.style.setProperty("--my", y.toFixed(3));
      });
    };
    window.addEventListener("pointermove", onMove, { passive: true });
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("pointermove", onMove);
    };
  }, []);
  return null;
}
