// Measures how much a page reads like an article, for deciding whether to offer reader mode.
// Sela runs this in its own script world once a page has loaded. It only reads the page.
JSON.stringify((() => {
    const text = (element) => (element.textContent || "").replace(/\s+/g, " ").trim();
    const isShown = (element) => element.getClientRects().length > 0;

    let longParagraphs = 0;
    let paragraphCharacters = 0;
    for (const paragraph of document.querySelectorAll("p")) {
        if (!isShown(paragraph)) continue;
        const length = text(paragraph).length;
        if (length < 80) continue;
        // Paragraphs that are mostly links are menus and lists of stories, not prose.
        let linked = 0;
        for (const link of paragraph.querySelectorAll("a")) linked += text(link).length;
        if (linked > length / 2) continue;
        longParagraphs += 1;
        paragraphCharacters += length;
    }

    const openGraphType = (document.querySelector('meta[property="og:type"]')?.content || "").toLowerCase();
    const structuredData = [...document.querySelectorAll('script[type="application/ld+json"]')].map((s) => s.textContent).join(" ");
    const articleTypes = /"@type"\s*:\s*\[?\s*"(Article|NewsArticle|BlogPosting|Report|TechArticle|ScholarlyArticle|AnalysisNewsArticle|OpinionNewsArticle)"/;

    return {
        longParagraphs,
        paragraphCharacters,
        hasArticleElement: document.querySelector("article") !== null,
        isMarkedAsArticle: openGraphType === "article" || articleTypes.test(structuredData),
        formFields: document.querySelectorAll('input:not([type="hidden"]), textarea, select').length,
        path: location.pathname,
    };
})());
