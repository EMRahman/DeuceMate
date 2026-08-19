# App Store advertisement frames — build source

The three art-directed frames that lead the iPhone gallery. Everything here is a
**render source**, not a published page: `docs/_config.yml` excludes this folder
from GitHub Pages.

```bash
./build.sh
```

Writes `01-watch-and-iphone.png`, `02-match-analysis.png` and `03-ai-coach.png`
into [`../iphone-6.9-marketing/`](../iphone-6.9-marketing/) at **1320 x 2868,
no alpha** — the same size as the raw `iphone-6.9/` set, because the App Store
requires one consistent size across an iPhone screenshot set.

## What each frame says

| Frame | Headline | Why it exists |
|---|---|---|
| 01 | Score on your **wrist**. | The one thing the old gallery never said: this is an Apple Watch scorer, and the iPhone is its companion. The Watch is oversized relative to true scale and sits in front of the phone so the score survives thumbnail size. |
| 02 | See where the match **turned**. | The momentum graph is the most distinctive image the app produces. |
| 03 | Hand your match to an **AI coach**. | The differentiator — the "Open in ChatGPT / Claude / Gemini" rows are the payload of the frame. |

Copy lives in the `<h1>` and `<p class="subhead">` of each HTML file. Changing a
word is a one-line edit plus a re-run.

## How it works

No new tooling: `build.sh` drives **`DeuceMateWebSnapshot`**, the macOS Swift
executable in `Packages/DeuceMateCore` that renders a local HTML file through a
headless `WKWebView`. It is the same tool that produced shots 10–14 in
`docs/screenshots/`.

Four constraints shape the script. Each was measured, not assumed, and each
will silently ruin the output if it is forgotten:

1. **The snapshot renders at the display's 2x backing scale.** Asking for
   `1400 1600` yields a 2800x3200 PNG. So the frames are authored in **660 x
   1434 CSS px** and land at 1320 x 2868. Do not "correct" the CSS to the
   pixel dimensions — you would get a 2640 x 5736 image, which no iPhone
   screenshot slot accepts.
2. **Its PNGs carry an alpha channel**, and App Store Connect rejects those.
   `build.sh` flattens each to RGB with Pillow.
3. **`WKWebView`'s file read access is scoped to the HTML file's own
   directory.** A `../` image reference will silently fail to load. So the
   script stages the HTML, the CSS, and every source PNG together in one temp
   directory under flat `src-*.png` names.
4. **Sources live in two directories at three different sizes.** Staging
   normalises that too.

`build.sh` asserts the size and the absence of alpha after every render and
fails loudly, because those are the two ways this breaks without looking broken.

Output is byte-for-byte identical across runs.

## Sources

| Staged as | From |
|---|---|
| `src-watch-live.png` | `../watch-45mm/01-watch-live-scoreboard.png` |
| `src-iphone-archive.png` | `../iphone-6.9/05-match-archive.png` |
| `src-iphone-graph.png` | `sources/points-graph-dark.png` |
| `src-iphone-aicoach.png` | `../../screenshots/09-ai-coach-launcher.png` |

`sources/` holds captures that exist **only** for these frames. The dark Points
Graph lives there rather than replacing `../iphone-6.9/02-points-momentum.png`,
which stays the light 1320 x 2868 capture uploaded as a raw screenshot in its
own right.

Replacing a source screenshot means re-running the build; the frames are not
edited by hand and nothing here is retouched.

## Checking the result

Dimensions and alpha are asserted automatically. The judgement calls are not,
so before uploading:

- **Look at each PNG full size.** Text unclipped, nothing overlapping, the Watch
  score legible.
- **Look at them at ~25%.** That approximates an App Store search result, which
  is where most people will actually see them. If the headline or the Watch
  score cannot be read there, the frame has failed at its real job — scale the
  type or the devices up and re-run.

## Light and dark, and why they are mixed

Frames 02 and 03 embed dark-mode screenshots; **01 is deliberately light**, and
that is not an oversight.

Both were built and compared at thumbnail size, which is where most people see
a store screenshot. Ad 01's entire job is to say *Apple Watch scorer, iPhone
companion* — and it only does that if a viewer registers **two** devices. The
bright phone behind the dark Watch is what makes that read at 300px wide. In the
dark version the two merge into one slab, even with the Watch's rim and glow
pushed up to compensate. At full size dark looks more premium; at thumbnail size
it loses the point of the frame, so light wins on the size that matters.

Ads 02 and 03 have no such job — a single device, no separation to preserve — so
they take the dark captures, which sit with the backdrop instead of punching a
white slab through it.

If ad 01 is ever revisited, compare at thumbnail size before deciding; full-size
review will mislead you here.
