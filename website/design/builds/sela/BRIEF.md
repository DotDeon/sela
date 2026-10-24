# Sela landing page brief

**Self-authored under explicit creative delegation.** On 2026-10-24 the owner answered the eight questions with "judgment". Their earlier answers stand as the only verbatim input:

- Audience: "Arc refugees"
- Money: "Donations only", through GitHub Sponsors
- Site: "website should be nextjs", copy through unslop
- Assets: real app, no generated imagery

Everything below that isn't quoted is my decision.

## Facts the page may use

These come from the README and the code:

- Free and open source, GPL-3.0, at github.com/DotDeon/sela
- Mac only, macOS 15 or later, built on WebKit with a native Swift interface
- Arc's sidebar model: favourites, pinned tabs, folders, unpinned tabs that archive themselves after 12 hours, and spaces you swipe between
- On first launch it offers to bring in your Arc sidebar, plus the last 90 days of Arc history
- Command bar on Cmd+T, split view of up to four tabs, Peek for links from pinned tabs and favourites
- Ads and trackers blocked with AdGuard Base and EasyPrivacy, and it can be turned off per site
- Tabs unused for 15 minutes go to sleep to save memory, and wake where they were
- Downloads files, finds text with Cmd+F, and asks before sites use the camera or microphone

**Not claimed:**
- YouTube ad blocking. The owner reported it still fails, even though the README says it works.
- Any memory figures, because no measured numbers have been published.
- A shutdown date for Arc.

## The eight topics

1. **Vibe:** calm, exact, a bit warm. Like moving house with a friend who labels every box. References:
   - a Muji storage aisle
   - the macOS 9 Finder
   - the moving-day scene in *Up*, where the whole house goes along.
2. **Journey:**
   1. A Sela window, already open.
   2. Arc has stopped growing.
   3. Your sidebar moves across.
   4. What the browser does day to day.
   5. Ads are gone.
   6. The fine print: free, open source, which Mac.
   7. A command bar you type into, to download or sponsor.
3. **Energy:**
   - Calm at the open.
   - Quieter still on Arc stopping.
   - The most active moment is the move.
   - Busy but light through the features.
   - Brisk on ads.
   - Flat on the fine print.
   - Still at the close.
4. **Feeling and the one moment:** in the feeling curve below.
5. **The thing no other site does:** the site's own navigation is a browser sidebar, and partway down, a sample Arc sidebar empties itself into it. You then get around the page with the sidebar that just arrived.
6. **Style range:** precise and product-led, not premium-minimal. Light silver ground, Sela's own teal as the one accent, dense small labels where a real app would have them.
7. **World:** one working surface, the Sela window, not scenes. The page is a page open inside Sela.
8. **Assets:** the real app and its icon only. The window on the page is working markup with sample data, labelled as a sample where it shows data.

## Grammar

Live surface. The pitch is "it works like the Arc you already know", so the honest demo is the surface itself.

The other seven lose:
- **Filmic one-shot:** carried, not operating. These visitors already know the product category and want to touch it.
- **Chaptered editorial:** nobody needs a long read to switch browsers.
- **Continuous world:** there's no geography to travel through.
- **Typographic poster:** the argument is a working sidebar, not a sentence.
- **Gallery:** there's one product, not a range.
- **Split stage:** tempting with Arc against Sela, but it would turn the page into a comparison, and Sela isn't trying to beat Arc.
- **Rhythmic cutlist:** wrong energy for people being careful with a move.

## Feeling curve

1. **Recognition.** A browser window with a sidebar exactly where their hands expect it. The page is already inside it.
2. **Quiet loss.** One short paragraph on Arc no longer being built, small type, lots of space, nothing moving. This is authored silence before the peak, not dead scroll.
3. **Relief, the peak.** A sample Arc sidebar sits in the page. As they scroll, its spaces, pinned tabs and folders lift out one by one and land in the real sidebar on the left, in the same order, while an import log counts them.
4. **Ease.** Small working surfaces slide past sideways: split view, Peek, sleeping tabs, archiving, the command bar. Each one is shown doing its thing.
5. **Satisfaction.** A cluttered sample article, then a wipe, and the ad slots are gone. A count says how many were removed from this page.
6. **Trust.** The plain facts: free, GPL, WebKit, macOS 15, no account.
7. **Resolve.** Everything stops. A command bar with a blinking cursor, "Download Sela for Mac" already highlighted, and Sponsor one arrow key away.

## The peak

> "I scrolled and my Arc sidebar emptied itself into the site's sidebar, and then I used it to get around."

It lives in act 3, and it gets the largest span on the page.

## Tell someone

It's the site where your Arc tabs fly out of Arc and land in the sidebar you then use to get around the page.

## Signature move

The sidebar move. Items travel by FLIP from the sample Arc panel inside a pinned stage to their slots in the page's fixed sidebar, driven by the act's progress. They stay there for the rest of the visit and work as navigation.

On a phone there is no fixed sidebar, so the items travel into a Sela panel stacked below the Arc one.

## Authored silence

Act 2 is meant to be quiet: small type, no motion, about one screen. The verification pass should read it as silence, not dead scroll.

## Score

| Act | Beat | Device | Span | Why this one |
|---|---|---|---|---|
| 1 Sela | Recognition | `pin`, layered planes driven by `--sc-p` | 1.6 | The surface is already open. Arc's window falls back behind it while Sela's import sheet rises past |
| 2 Leaving Arc | Quiet loss | `flow` + `in` | about 1 | Plain reading, no motion: the silence before the peak |
| 3 The move | Relief (peak) | `pin`, page-local flight | 3.8 | Holds the frame while the sidebar moves item by item |
| 4 Every day | Ease | `pan` | 3.0 | Sideways travel reads as range. Each card is a working control |
| 5 Ad blocking | Satisfaction | `pin` + `reveal` + `count` | 1.6 | A wipe is a change of state: cluttered, then clean |
| 6 Fine print | Trust | `flow` + `in` | about 0.9 | Admin facts, compressed |
| 7 Get Sela | Resolve | `pin`, a real command bar | 1.2 | The surface hands over an input, not a button island |

The page uses five families: `pin`, `flow`, `pan`, `reveal` and `count`. No family repeats in adjacent acts. The total is about 13.1 viewport-heights across 7 acts, outside the 13.6 to 13.8 band.
