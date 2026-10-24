"use client";

import { useId, useState } from "react";

type Block = { kind: "text"; text: string } | { kind: "ad"; size: "wide" | "box" };

const article: Block[] = [
  { kind: "ad", size: "wide" },
  { kind: "text", text: "Fry an onion in olive oil until soft. Add two cloves of garlic and a spoon of cumin." },
  { kind: "ad", size: "box" },
  { kind: "text", text: "Stir in a cup of red lentils, a tin of tomatoes and a litre of stock." },
  { kind: "ad", size: "wide" },
  { kind: "text", text: "Simmer for twenty minutes, then finish with lemon juice and salt." },
  { kind: "ad", size: "box" },
];

const adCount = article.filter((b) => b.kind === "ad").length;

function Page({ blocked }: { blocked: boolean }) {
  return (
    <div className="recipe" data-blocked={blocked || undefined}>
      <p className="recipe__title">Weeknight lentil soup</p>
      {article.map((b, i) =>
        b.kind === "text" ? (
          <p key={i} className="recipe__text">
            {b.text}
          </p>
        ) : blocked ? null : (
          <div key={i} className={`ad ad--${b.size}`}>
            Advertisement
          </div>
        ),
      )}
    </div>
  );
}

export function AdAct() {
  const [on, setOn] = useState(true);
  const id = useId();
  return (
    <section id="ad-blocking" className="ads" data-sc-act="pin" data-sc-span="1.6">
      <div data-sc-stage className="ads__stage">
        <div className="ads__copy">
          <h2 className="heading">Ads and trackers are blocked from the start.</h2>
          <p className="body">
            Sela blocks them with the AdGuard Base and EasyPrivacy filter lists, which it keeps up
            to date. If a site breaks, turn blocking off for that site.
          </p>
          <p className="ads__count" data-off={on ? undefined : ""}>
            <span className="ads__count-on">
              <span className="nums">{adCount}</span>{" "}
              ads removed from this sample page.
            </span>
            <span className="ads__count-off">Blocking is off for this sample page.</span>
          </p>
        </div>

        <figure className="ads__window">
          <div className="ads__bar">
            <span className="ads__site">recipes.example</span>
            <label className="switch" htmlFor={id}>
              <input id={id} type="checkbox" checked={on} onChange={(e) => setOn(e.target.checked)} />
              <span>Block on this site</span>
            </label>
          </div>
          <div className="ads__pages">
            <Page blocked={false} />
            <div className="ads__clean" data-off={on ? undefined : ""} data-sc-reveal="down" data-sc-reveal-at="0.2 0.62">
              <Page blocked />
            </div>
          </div>
          <figcaption className="caption">A sample page. Real sites differ.</figcaption>
        </figure>
      </div>
    </section>
  );
}
