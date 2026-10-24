"use client";

import Script from "next/script";
import { asset } from "@/lib/site";

declare global {
  interface Window {
    ScrollCraft?: { mount: (root: Element) => void };
  }
}

// Loads the scroll runtime after hydration, so it only ever drives markup
// React has already rendered.
export function Engine() {
  return (
    <Script
      src={asset("/scrollcraft.js")}
      strategy="afterInteractive"
      onReady={() => {
        const root = document.body;
        if (root.dataset.scMounted) return;
        root.dataset.scMounted = "1";
        window.ScrollCraft?.mount(root);
      }}
    />
  );
}
