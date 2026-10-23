// Runs at document start in every frame, in Brow's own content world, so pages can't see or call it.
// Asks Brow for the advanced blocking rules that apply here, then applies them with AdGuard's content script.
import { ContentScript } from '@adguard/safari-extension';

const bridge = window.webkit?.messageHandlers?.browContentBlocking;
if (bridge) {
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
