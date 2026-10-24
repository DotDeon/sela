// Ad blocking as a change of state: the same water, first clouded and covered
// in sample ad slots, then wiped clear.
const slots = [
  { x: 0.08, y: 0.12, w: 0.24, h: 0.1 },
  { x: 0.62, y: 0.08, w: 0.16, h: 0.26 },
  { x: 0.14, y: 0.58, w: 0.2, h: 0.22 },
  { x: 0.4, y: 0.34, w: 0.3, h: 0.09 },
  { x: 0.5, y: 0.7, w: 0.22, h: 0.12 },
];

export function ClearWater() {
  return (
    <section id="clear-water" className="clear" data-sc-act="pin" data-sc-span="1.8">
      <div data-sc-stage className="clear__stage">
        <div className="clear__before" aria-hidden>
          <img className="clear__image clear__image--murky" src="/media/clear.jpg" alt="" />
          {slots.map((s, i) => (
            <span
              key={i}
              className="ad"
              style={{ left: `${s.x * 100}%`, top: `${s.y * 100}%`, width: `${s.w * 100}%`, height: `${s.h * 100}%` }}
            >
              Ad
            </span>
          ))}
        </div>
        <div className="clear__after" data-sc-reveal="right" data-sc-reveal-at="0.12 0.6">
          <img
            className="clear__image"
            src="/media/clear.jpg"
            alt="Clear shallow water over smooth dark pebbles"
          />
        </div>
        <div className="sc-scrim clear__scrim" aria-hidden />
        <div className="clear__copy" data-sc-cue="0.06 1 0.08 0.04">
          <h2 className="heading">Ads and trackers are blocked from the start.</h2>
          <p className="body">
            Sela uses the AdGuard Base and EasyPrivacy filter lists and keeps them up to date. If
            a site breaks, turn blocking off for that site.
          </p>
        </div>
      </div>
    </section>
  );
}
