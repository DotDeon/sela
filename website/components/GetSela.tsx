import { CommandBar } from "./CommandBar";

// The close ends on Sela's command bar, full size. The same bar is docked at the
// foot of the sidebar, so nobody has to scroll here to use it.
export function GetSela() {
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

          <div className="close__command" data-sc-cue="0.06" data-sc-rise="0">
            <CommandBar />
          </div>
        </div>

        <footer className="foot">
          <p>Sela is free software under the GNU GPL, version 3.</p>
        </footer>
      </div>
    </section>
  );
}
