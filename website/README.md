# Sela website

The landing page for Sela, a Next.js site that exports to static files.

```bash
npm install
npm run dev     # http://localhost:3000
npm run build   # writes the static site to out/
```

- `app/` holds the page, layout and styles.
- `components/` holds one file per act, plus the sidebar.
- `lib/site.ts` holds the links and section list.
- `public/scrollcraft.js` and `app/scrollcraft.css` are the scroll runtime. Change the page's own code, not these.
- `design/` holds the brief, the score and the fingerprint record behind the page.
