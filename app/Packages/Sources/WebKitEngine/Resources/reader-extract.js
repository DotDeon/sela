// Finds a page's article and returns it as clean HTML, for reader mode.
// Sela runs this in its own script world. It reads the page without changing it, and rebuilds the article
// from a short list of safe elements and attributes, so nothing from the page can run in the reader.
JSON.stringify((() => {
    const NEGATIVE = /comment|meta|footer|footnote|share|social|related|sidebar|widget|promo|advert|sponsor|newsletter|subscribe|signup|nav|menu|breadcrumb|cookie|consent|popup|modal|banner|masthead|toolbar|recirc|outbrain|taboola/i;
    const POSITIVE = /article|body|content|entry|main|post|text|blog|story|prose/i;
    const DROP = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "IFRAME", "FRAME", "OBJECT", "EMBED", "FORM", "BUTTON", "INPUT", "SELECT",
        "TEXTAREA", "LABEL", "NAV", "ASIDE", "FOOTER", "HEADER", "SVG", "CANVAS", "VIDEO", "AUDIO", "SOURCE", "TRACK", "DIALOG", "MENU", "LINK", "META"]);
    const KEEP = new Set(["P", "H2", "H3", "H4", "H5", "H6", "A", "IMG", "FIGURE", "FIGCAPTION", "BLOCKQUOTE", "PRE", "CODE", "UL", "OL", "LI",
        "DL", "DT", "DD", "EM", "I", "STRONG", "B", "U", "S", "MARK", "SMALL", "SUB", "SUP", "BR", "HR", "TABLE", "THEAD", "TBODY", "TFOOT",
        "TR", "TH", "TD", "CAPTION", "ABBR", "CITE", "Q", "TIME", "KBD", "VAR", "SAMP", "PICTURE", "DEL", "INS"]);
    // Kept as plain blocks, so the article keeps its paragraphs and sections apart.
    const BLOCKS = new Set(["DIV", "SECTION", "ARTICLE", "MAIN"]);

    const text = (element) => (element.textContent || "").replace(/\s+/g, " ").trim();
    const hints = (element) => `${typeof element.className === "string" ? element.className : ""} ${element.id || ""} ${element.getAttribute("role") || ""}`;
    const weight = (element) => {
        let score = 0;
        const words = hints(element);
        if (NEGATIVE.test(words)) score -= 25;
        if (POSITIVE.test(words)) score += 25;
        if (element.tagName === "ARTICLE") score += 25;
        if (element.tagName === "MAIN") score += 10;
        return score;
    };
    const linkDensity = (element) => {
        const length = text(element).length;
        if (length === 0) return 1;
        let linked = 0;
        for (const link of element.querySelectorAll("a")) linked += text(link).length;
        return linked / length;
    };
    const isHidden = (element) => {
        if (element.hidden || element.getAttribute("aria-hidden") === "true") return true;
        const style = getComputedStyle(element);
        return style.display === "none" || style.visibility === "hidden";
    };

    // Each paragraph adds to its parent's score, and less to the ancestors above that.
    const scores = new Map();
    for (const paragraph of document.querySelectorAll("p, pre, blockquote, td")) {
        const content = text(paragraph);
        if (content.length < 25) continue;
        const points = 1 + content.split(/[,，、]/).length + Math.min(Math.floor(content.length / 100), 3);
        let ancestor = paragraph.parentElement;
        for (let level = 0; ancestor && ancestor !== document.documentElement && level < 3; level += 1) {
            if (!scores.has(ancestor)) scores.set(ancestor, weight(ancestor));
            scores.set(ancestor, scores.get(ancestor) + points / (level === 0 ? 1 : level * 2));
            ancestor = ancestor.parentElement;
        }
    }
    let best = null;
    let bestScore = 0;
    for (const [element, score] of scores) {
        const adjusted = score * (1 - linkDensity(element));
        if (adjusted > bestScore) {
            best = element;
            bestScore = adjusted;
        }
    }
    if (!best) return null;
    // A best guess that holds only part of the story widens to the parent when the parent holds more prose.
    const parent = best.parentElement;
    if (parent && parent !== document.body && scores.has(parent) && scores.get(parent) * (1 - linkDensity(parent)) > bestScore * 0.75) {
        best = parent;
    }

    const output = document.implementation.createHTMLDocument("");
    const absolute = (value, schemes) => {
        if (!value) return null;
        try {
            const url = new URL(value, document.baseURI);
            return schemes.includes(url.protocol) ? url.href : null;
        } catch {
            return null;
        }
    };
    // Lazy-loading pages keep the real image address in a data attribute until it scrolls into view.
    const imageSource = (image) => {
        for (const value of [image.currentSrc, image.getAttribute("data-src"), image.getAttribute("data-original"), image.getAttribute("data-lazy-src"), image.getAttribute("src")]) {
            const url = absolute(value, ["http:", "https:"]);
            if (url) return url;
        }
        return null;
    };
    const isClutter = (element) => {
        if (NEGATIVE.test(hints(element)) && !POSITIVE.test(hints(element))) {
            const length = text(element).length;
            return length < 500 || linkDensity(element) > 0.3;
        }
        if (["UL", "OL", "DIV", "SECTION", "TABLE"].includes(element.tagName)) {
            return linkDensity(element) > 0.6 && text(element).length < 1000;
        }
        return false;
    };

    const copy = (node, into) => {
        if (node.nodeType === Node.TEXT_NODE) {
            into.appendChild(output.createTextNode(node.textContent));
            return;
        }
        if (node.nodeType !== Node.ELEMENT_NODE) return;
        const element = node;
        const tag = element.tagName.toUpperCase();
        if (DROP.has(tag) || isHidden(element) || isClutter(element)) return;
        if (tag === "PICTURE") {
            const image = element.querySelector("img");
            if (image) copy(image, into);
            return;
        }
        let made = null;
        if (tag === "H1") {
            made = output.createElement("h2");
        } else if (BLOCKS.has(tag)) {
            made = output.createElement("div");
        } else if (KEEP.has(tag)) {
            made = output.createElement(tag.toLowerCase());
        }
        if (tag === "IMG") {
            const source = imageSource(element);
            if (!source) return;
            made.setAttribute("src", source);
            if (element.alt) made.setAttribute("alt", element.alt);
            into.appendChild(made);
            return;
        }
        if (tag === "A") {
            const href = absolute(element.getAttribute("href"), ["http:", "https:", "mailto:"]);
            if (href) made.setAttribute("href", href);
        }
        if ((tag === "TD" || tag === "TH") && element.colSpan > 1) made.setAttribute("colspan", String(element.colSpan));
        const target = made || into;
        for (const child of element.childNodes) copy(child, target);
        if (made) into.appendChild(made);
    };
    const container = output.createElement("div");
    for (const child of best.childNodes) copy(child, container);

    // Empty blocks left behind by removed widgets.
    for (const element of [...container.querySelectorAll("p, div, li, figure, h2, h3, h4, h5, h6, blockquote")].reverse()) {
        if (text(element) === "" && !element.querySelector("img, hr, br")) element.remove();
    }

    const meta = (selector) => document.querySelector(selector)?.getAttribute("content")?.trim() || "";
    const heading = best.querySelector("h1") || document.querySelector("article h1, main h1, h1");
    let title = heading ? text(heading) : "";
    if (!title) title = meta('meta[property="og:title"]') || document.title.trim();
    // The article's own heading shows once, above the text.
    const first = container.querySelector("h2");
    if (first && text(first) === title) first.remove();

    const bylineElement = best.querySelector('[rel="author"], [itemprop="author"], .byline, .author') || document.querySelector('[rel="author"], [itemprop="author"] [itemprop="name"], .byline');
    let byline = meta('meta[name="author"]') || (bylineElement ? text(bylineElement) : "");
    if (byline.length > 100) byline = "";

    return {
        title,
        byline,
        siteName: meta('meta[property="og:site_name"]') || location.hostname.replace(/^www\./, ""),
        content: container.innerHTML,
        textLength: text(container).length,
        language: document.documentElement.lang || "",
    };
})());
