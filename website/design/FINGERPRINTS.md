# Fingerprints

Every site you build with **scroll-craft** gets one row here, appended after it
ships. The registry exists so your next build can prove it is a different page
rather than a re-skin of one you already made.

This file is **yours**. It starts empty on purpose: the gate is about not
repeating *yourself*, so it has nothing to say until you have built something.

The rules and the gate live in the skill's
`references/uniqueness.md`. Short version:

**A new build must differ from EVERY row below on at least 4 of the 6
dimensions.** Four against each row individually, not four on average across the
table. If a planned build fails, change the plan. Never edit a row to make room
for it.

The six dimensions are: **grammar**, **nav treatment**, **hero device**,
**act-sequence shape**, **close pattern**, **signature move**.

Dimension 6 is free, because a signature move is unique by definition. So the
gate really asks for three more out of the remaining five, and a build that
changes only grammar and world will fail it.

---

## The registry

| Build | Grammar | Nav treatment | Hero device | Act-sequence shape | Close pattern | Signature move | World | Port |
|---|---|---|---|---|---|---|---|---|
| sela (2026-10-24) | Live surface | A fixed browser sidebar is the nav: favourites, pinned tabs per section, a space bar | The Sela window already open, with Arc receding behind an import sheet as three planes | pin > flow > pin (peak, 3.8) > pan > pin + reveal > flow > pin, 7 acts, about 12.9vh | A working command bar with Download highlighted, footer inside the stage | Tabs fly out of a sample Arc sidebar into the site's own nav and stay there | Light silver Mac chrome, one teal accent | Next.js static export |
| sela-2 (2026-10-24) | Framed film (new) | Same fixed browser sidebar as nav, dark | Scrubbed push-in on a stone in a river, mist planes front and back | scrub > pin > scrub (peak, 3.6) > pan > pin + reveal > flow > pin, 7 acts, about 15vh | Command bar floating over a still lake at dawn | Scroll runs the river, and pinned tabs climb out into the sidebar while loose ones float away | Dark low-key river at blue hour | Next.js static export |

---

## What is taken

Add a bullet here whenever a build claims something a later build should avoid
reusing: a grammar, a nav treatment, a close pattern, a signature move, an
act-count-and-length band. The shared columns are what the next build inherits
as a constraint, so writing them down is the whole point.

- Live surface with the site's nav as the product's own sidebar (sela)
- Items flying from a sample panel into fixed chrome (sela)
- A command bar as the close (sela, sela-2)
- Framed film: product chrome around full-bleed generated footage (sela-2)

---

## Appending a row

After shipping, add one line to the table and one bullet to **What is taken** if
the build claimed something new. Fill every column. Say what the build shares
with existing rows.

Rows are append-only. A build that has been superseded stays in the table,
because the space it occupies is still occupied.

---

## Worked example

The skill's author kept a registry of twelve builds across eight page grammars.
If you want to see what a filled-in table looks like, and which shapes tend to
collide, read `EXAMPLES.md` in the scroll-craft repository. Treat it as
illustration only: those rows are somebody else's builds and they do **not**
constrain yours.
