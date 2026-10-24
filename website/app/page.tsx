import { AdAct } from "@/components/AdAct";
import { ArcPanel } from "@/components/ArcPanel";
import { Chrome } from "@/components/Chrome";
import { Engine } from "@/components/Engine";
import { EveryDay } from "@/components/EveryDay";
import { GetSela } from "@/components/GetSela";
import { HeroDepth } from "@/components/HeroDepth";
import { MoveAct } from "@/components/MoveAct";
import { downloadLabel, links } from "@/lib/site";

const facts = [
  { term: "Price", detail: "Free. Sponsors on GitHub pay for the work." },
  { term: "Licence", detail: "GNU GPL, version 3. The code is on GitHub." },
  { term: "Engine", detail: "WebKit, the engine Safari uses, with a native Mac interface." },
  { term: "Needs", detail: "macOS 15 or later." },
  { term: "Account", detail: "None. There's nothing to sign in to." },
  {
    term: "Passwords",
    detail: "Sela can't read Arc's saved passwords. Export them to a CSV file from Arc's settings first.",
  },
];

export default function Home() {
  return (
    <>
      <Chrome />
      <main className="web">
        <section id="sela" className="hero" data-sc-act="pin" data-sc-span="1.6">
          <div data-sc-stage className="hero__stage">
            <div className="hero__copy">
              <h1 className="display">Leaving Arc? Bring your sidebar.</h1>
              <p className="lede">
                Sela is a free, open-source Mac browser that works like Arc. Your spaces, pinned
                tabs and folders come with you.
              </p>
              <p className="hero__actions">
                <a className="button" href={links.download}>
                  {downloadLabel}
                </a>
                <span className="hero__note">macOS 15 or later</span>
              </p>
            </div>

            <div className="hero__planes" aria-hidden>
              <div className="plane plane--arc">
                <ArcPanel />
              </div>
              <div className="plane plane--sheet">
                <div className="sheet">
                  <p className="sheet__title">Bring your Arc sidebar into Sela?</p>
                  <p className="sheet__text">
                    Sela can copy your spaces, pinned tabs, folders and favourites from Arc. Arc
                    isn&rsquo;t changed.
                  </p>
                  <p className="sheet__buttons">
                    <a href="#every-day" tabIndex={-1} className="sheet__button">
                      Start Fresh
                    </a>
                    <a href="#the-move" tabIndex={-1} className="sheet__button sheet__button--primary">
                      Import
                    </a>
                  </p>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="leaving-arc" className="leaving">
          <div className="leaving__inner" data-sc-in data-sc-stagger="80">
            <p className="quiet">
              In 2025 The Browser Company stopped building new things for Arc and moved on to Dia.
              Arc still opens. Nobody is making it better.
            </p>
            <p className="quiet quiet--turn">
              Most of us didn&rsquo;t pick Arc for its engine. We picked it for the sidebar.
            </p>
          </div>
        </section>

        <MoveAct />
        <EveryDay />
        <AdAct />

        <section id="fine-print" className="fine">
          <div className="fine__inner" data-sc-in data-sc-stagger="50">
            <h2 className="heading heading--small">The short version</h2>
            <dl className="facts">
              {facts.map((f) => (
                <div key={f.term} className="fact">
                  <dt>{f.term}</dt>
                  <dd>{f.detail}</dd>
                </div>
              ))}
            </dl>
          </div>
        </section>

        <GetSela />
      </main>
      <HeroDepth />
      <Engine />
    </>
  );
}
