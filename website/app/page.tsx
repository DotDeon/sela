import { Chrome } from "@/components/Chrome";
import { ClearWater } from "@/components/ClearWater";
import { Engine } from "@/components/Engine";
import { EveryDay } from "@/components/EveryDay";
import { GetSela } from "@/components/GetSela";
import { RiverAct } from "@/components/RiverAct";
import { downloadLabel, links } from "@/lib/site";

const facts = [
  { term: "Price", detail: "Free. Sponsors on GitHub pay for the work." },
  { term: "Licence", detail: "GNU GPL, version 3. The code is on GitHub." },
  { term: "Engine", detail: "WebKit, the engine Safari uses, with a native Mac interface." },
  { term: "Needs", detail: "macOS 15 or later." },
  { term: "Account", detail: "None. There's nothing to sign in to." },
  { term: "Memory", detail: "Tabs you haven't looked at for 15 minutes sleep, and wake where you left them." },
];

export default function Home() {
  return (
    <>
      <Chrome />
      <main className="web">
        <section id="sela" className="hero" data-sc-act="scrub" data-sc-span="2.4" data-sc-dwell="0.3">
          <div data-sc-stage>
            <picture>
              <source media="(max-width: 860px)" srcSet="/media/hero-poster-m.jpg" />
              <img className="sc-stage__poster" src="/media/hero-poster.jpg" alt="" />
            </picture>
            <video
              data-sc-scrub
              data-sc-src="/media/hero.mp4"
              data-sc-src-mobile="/media/hero-m.mp4"
              muted
              playsInline
            />
            <div className="mist mist--far" data-sc-parallax="-1.2" aria-hidden />
            <div className="sc-scrim hero__scrim" aria-hidden />
            <div className="hero__copy" data-sc-cue="0 0.72 0">
              <h1 className="display">A browser that holds still.</h1>
              <p className="lede">
                Sela is a free, open-source Mac browser. Your tabs rest in a calm sidebar while the
                web rushes past.
              </p>
              <p className="hero__actions">
                <a className="button" href={links.download}>
                  {downloadLabel}
                </a>
                <span className="hero__note">macOS 15 or later</span>
              </p>
            </div>
            <div className="mist mist--near" data-sc-parallax="1.6" aria-hidden />
          </div>
        </section>

        <section id="rock" className="rock" data-sc-act="pin" data-sc-span="2.2">
          <div data-sc-stage className="rock__stage">
            <p className="rock__line rock__line--name" data-sc-cue="0 0.34 0">
              <span lang="he">סֶלַע</span> Sela. An old Hebrew word for rock.
            </p>
            <p className="rock__line" data-sc-cue="0.28 0.66">
              The web never stops moving. Pages reload, feeds refresh, tabs pile up.
            </p>
            <p className="rock__line rock__line--turn" data-sc-cue="0.6 1 0.12 0.06">
              Your browser should be the one thing that doesn&rsquo;t.
            </p>
          </div>
        </section>

        <RiverAct />
        <EveryDay />
        <ClearWater />

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
      <Engine />
    </>
  );
}
