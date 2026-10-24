// Runs at document start in every frame, in Brow's own content world, so pages can't see or call it.
// Applies the advanced blocking rules for this page with AdGuard's content script. In the main frame Brow puts
// the rules here before the page loads, so they apply before the page's own scripts run. Frames ask Brow for theirs.
import { ContentScript } from '@adguard/safari-extension';

const early = window === window.top ? window.__browEarlyRules : undefined;
const bridge = window.webkit?.messageHandlers?.browContentBlocking;
if (early) {
    new ContentScript().applyConfiguration({ ...early, engineTimestamp: 0 });
} else if (bridge) {
    const origins = location.ancestorOrigins;
    const top = window === window.top || !origins || origins.length === 0 ? null : origins[origins.length - 1];
    bridge.postMessage({ page: location.href, top })
        .then((rules) => {
            if (rules) {
                new ContentScript().applyConfiguration({ ...rules, engineTimestamp: 0 });
            }
        })
        .catch(() => {});
}
