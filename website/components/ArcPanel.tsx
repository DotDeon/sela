import { arcSections, arcSpaces } from "@/lib/site";
import { Favicon } from "./Icon";

// A sample Arc sidebar. Its pinned tabs are this page's remaining sections, so
// once they move into Sela's sidebar they work as the page's navigation.
export function ArcPanel({ flight = false }: { flight?: boolean }) {
  return (
    <div className="arc">
      <div className="arc__top">
        <span className="lights lights--muted" aria-hidden>
          <i /> <i /> <i />
        </span>
        <span className="arc__title">Arc</span>
      </div>
      <p className="arc__label">Personal</p>
      <ul className="arc__tabs">
        {arcSections.map((s) => (
          <li key={s.id} className="arc__tab" data-arc-item={flight ? s.id : undefined}>
            <Favicon name={s.icon} tint={s.tint} />
            <span>{s.title}</span>
          </li>
        ))}
      </ul>
      <div className="arc__spaces">
        {arcSpaces.map((s) => (
          <span
            key={s.id}
            className="space"
            data-arc-item={flight ? s.id : undefined}
            title={s.title}
            style={{ background: s.tint }}
          />
        ))}
      </div>
    </div>
  );
}
