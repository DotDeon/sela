// Collects a page's visible text for translation and writes translations back into the same text nodes.
// Sela runs this in its own script world, where it keeps the nodes it numbered and what they said before.
// `collect` starts watching the page so text that appears later is sent to Sela too; `restore` ends it.
(() => {
    if (window.__selaText) return;
    const SKIP = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "CODE", "PRE", "TEXTAREA", "INPUT", "SELECT", "OPTION",
        "SVG", "MATH", "IFRAME", "CANVAS", "KBD", "SAMP", "VAR"]);
    const MESSAGE_DELAY = 250;
    // Node number to its text node, what it said, and what Sela put there.
    const entries = new Map();
    let numbers = new WeakMap();
    let nextNumber = 0;
    let observer = null;
    let pending = [];
    let timer = null;

    const hasLetters = (text) => /\p{L}/u.test(text);
    let skipped = new WeakMap();
    // Whether an element, or anything above it, is one whose text is left alone: code, form fields, editors
    // and anything hidden. Remembered per element for the current walk, and forgotten when the page changes.
    const isSkipped = (element) => {
        if (!element || element === document.documentElement) return false;
        if (skipped.has(element)) return skipped.get(element);
        let result = true;
        if (!SKIP.has(element.tagName.toUpperCase()) && !element.isContentEditable && !element.hidden
            && element.getAttribute("aria-hidden") !== "true" && element.getAttribute("translate") !== "no") {
            const style = getComputedStyle(element);
            result = style.display === "none" || style.visibility === "hidden" || isSkipped(element.parentElement);
        }
        skipped.set(element, result);
        return result;
    };

    const register = (node) => {
        const text = node.nodeValue;
        const trimmed = text.trim();
        if (!trimmed || !hasLetters(trimmed) || isSkipped(node.parentElement)) return null;
        const number = nextNumber++;
        entries.set(number, { node, original: text, translated: null });
        numbers.set(node, number);
        return { id: number, text: trimmed };
    };

    const collect = (root) => {
        const segments = [];
        if (root.nodeType === Node.TEXT_NODE) {
            if (!numbers.has(root)) {
                const segment = register(root);
                if (segment) segments.push(segment);
            }
            return segments;
        }
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            if (numbers.has(node)) continue;
            const segment = register(node);
            if (segment) segments.push(segment);
        }
        return segments;
    };

    const send = () => {
        timer = null;
        if (pending.length === 0) return;
        const segments = pending;
        pending = [];
        window.webkit.messageHandlers.selaText.postMessage({ segments });
    };
    const queue = (segments) => {
        if (segments.length === 0) return;
        pending.push(...segments);
        if (!timer) timer = setTimeout(send, MESSAGE_DELAY);
    };

    const watch = () => {
        observer = new MutationObserver((mutations) => {
            skipped = new WeakMap();
            const added = [];
            for (const mutation of mutations) {
                if (mutation.type === "characterData") {
                    const node = mutation.target;
                    const number = numbers.get(node);
                    if (number === undefined) {
                        added.push(...collect(node));
                        continue;
                    }
                    // The page changed text Sela had translated, so the new text needs translating too.
                    const entry = entries.get(number);
                    if (node.nodeValue === entry.translated) continue;
                    entry.original = node.nodeValue;
                    entry.translated = null;
                    const trimmed = node.nodeValue.trim();
                    if (trimmed && hasLetters(trimmed)) added.push({ id: number, text: trimmed });
                } else {
                    for (const node of mutation.addedNodes) added.push(...collect(node));
                }
            }
            queue(added);
        });
        observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true });
    };

    window.__selaText = {
        collect() {
            skipped = new WeakMap();
            if (!observer) watch();
            return collect(document.body || document.documentElement);
        },
        // Keeps the space around each node's text, so words don't run into their neighbours.
        replace(segments) {
            for (const segment of segments) {
                const entry = entries.get(segment.id);
                if (!entry || entry.translated !== null && entry.node.nodeValue !== entry.translated) continue;
                const original = entry.original;
                const leading = original.match(/^\s*/)[0];
                const trailing = original.match(/\s*$/)[0];
                entry.translated = leading + segment.text + trailing;
                entry.node.nodeValue = entry.translated;
            }
        },
        restore() {
            if (observer) observer.disconnect();
            observer = null;
            if (timer) clearTimeout(timer);
            timer = null;
            pending = [];
            for (const entry of entries.values()) {
                if (entry.translated !== null && entry.node.nodeValue === entry.translated) entry.node.nodeValue = entry.original;
            }
            entries.clear();
            numbers = new WeakMap();
            nextNumber = 0;
        },
    };
})();
