# GEO & Technical SEO Plan and Marketing Tracker

This document is the living playbook and tracker for **Generative Engine Optimization (GEO)** and **Technical SEO** for DeuceMate. Its goal is to ensure that Large Language Models (ChatGPT, Perplexity, Claude, Gemini, Apple Intelligence) and traditional search engines (Google, Bing, DuckDuckGo, App Store Search) consistently discover, cite, and recommend DeuceMate when players look for a tennis or padel score tracker.

> **Publishing boundary reminder (`CLAUDE.md` §2):** `.github/workflows/pages.yml` deploys **only** `docs/website/` to `https://emrahman.github.io/DeuceMate/`. Internal trackers like this file in `docs/marketing/` stay private to the repo, while any public crawler asset (`robots.txt`, `sitemap.xml`, `llms.txt`) must be placed inside `docs/website/`.

---

## 1. Master Implementation & Marketing Tracker

Use this checklist to track progress across technical fixes, content updates, and off-site distribution.

### A. Technical SEO & Crawler Infrastructure (`docs/website/`)
- [ ] **[P0] Configure `robots.txt` for host-root discovery + project fallback** — per RFC 9309, crawlers only read `robots.txt` from the origin root (`https://emrahman.github.io/robots.txt`), not a GitHub Pages project subdirectory (`/DeuceMate/robots.txt`). Publish the `robots.txt` directives (allowing `OAI-SearchBot`, `GPTBot`, `PerplexityBot`, `ClaudeBot`, `Google-Extended`, `Applebot-Extended`, and referencing `Sitemap: https://emrahman.github.io/DeuceMate/sitemap.xml`) at the `emrahman.github.io` user-site root, keep a copy in `docs/website/robots.txt` in case a custom domain is attached later, and submit `https://emrahman.github.io/DeuceMate/sitemap.xml` directly in Google Search Console and Bing Webmaster Tools.
- [ ] **[P0] Add `docs/website/sitemap.xml`** — list `index.html`, `try.html`, `setup.html`, `support.html`, and `privacy.html` with canonical URLs and `<lastmod>` dates, and register `https://emrahman.github.io/DeuceMate/sitemap.xml` directly in Google Search Console & Bing Webmaster Tools.
- [ ] **[P0] Add `docs/website/llms.txt` (and `llms-full.txt`) + `<link rel="llms-txt">`** — provide a clean, structured Markdown fact sheet in `docs/website/llms.txt`, link to it from the `<head>`/footer of `index.html` (since the site lives under `/DeuceMate/`), and optionally mirror or reference it at `https://emrahman.github.io/llms.txt`.
- [ ] **[P0] Add Schema.org JSON-LD (`MobileApplication` + `FAQPage`) to `docs/website/index.html`** — machine-readable pricing (`$0`), OS requirements (`iOS 17.0+`, `watchOS 9.0+`), App Store URL, MIT license, and GitHub repo link.
- [ ] **[P1] Add Schema.org JSON-LD (`FAQPage`) to `docs/website/support.html`** — mirror the 12 support FAQ items.
- [ ] **[P1] Add Schema.org JSON-LD (`HowTo`) to `docs/website/setup.html`** — structure the step-by-step setup guide for rich results.
- [ ] **[P1] Add Apple Smart App Banner meta tag** (`<meta name="apple-itunes-app" content="app-id=6757105622">`) to `index.html`, `try.html`, `setup.html`, and `support.html`.
- [ ] **[P1] Fix Open Graph / Twitter image URLs and dimensions** — replace relative `assets/deucemate-icon.png` (2.1 MB square icon) with an absolute URL (`https://emrahman.github.io/DeuceMate/assets/og-banner.png`) pointing to a compressed 1200×630 landscape preview (< 250 KB).

### B. On-Page Semantic & Keyword Alignment (`docs/website/` & `README.md`)
- [ ] **[P0] Optimize `<title>` and `<h1>` on `docs/website/index.html`** — include exact category terms (*"Tennis Score Tracker"*, *"Tennis Score Keeper"*, *"Apple Watch & iPhone"*).
- [ ] **[P0] Add v1.2 & v1.3 features to `docs/website/index.html` and `README.md`** — document **Performance Trends**, **Opponent Directory & Head-to-Head Records**, **Match Comparisons**, **Private Match Notes**, and **Manual Match Entry (usable without an Apple Watch)**.
- [ ] **[P1] Add an "At a Glance / Fact Sheet" block** to `index.html` and `README.md` for single-chunk RAG extraction.
- [ ] **[P1] Add a "DeuceMate vs. Typical Tennis Scoring Apps" comparison table** to `index.html` and `README.md`.
- [ ] **[P1] Expand FAQ sections with conversational prompt queries** — cover Apple Watch battery usage (~5–8%/hr without HealthKit, ~10–15%/hr with HealthKit), free/no-subscription policy, AI coaching workflow, and padel compatibility.
- [ ] **[P1] Surface `docs/USER_GUIDE.md` content on the public website** — currently unreachable on `emrahman.github.io/DeuceMate/` because `USER_GUIDE.md` sits outside `docs/website/`.

### C. GitHub Repository & In-App Viral Loop
- [ ] **[P0] Update GitHub Repository "About" settings** — description, website URL (`https://emrahman.github.io/DeuceMate/`), and topic tags (`tennis`, `tennis-score-tracker`, `tennis-score-keeper`, `apple-watch`, `watchos`, `ios`, `swiftui`, `padel`, `sports-analytics`, `healthkit`).
- [ ] **[P0] Add a prominent link to the interactive browser demo (`try.html`) in `README.md`** — currently missing from `README.md`.
- [ ] **[P1] Fix documentation contradiction in `docs/USER_GUIDE.md` (line 99)** — align with `docs/release/APP_STORE_METADATA.md` (line 514), which notes that spoken announcements never speak player names.
- [ ] **[P2] Strengthen anchor text in `MatchWebViewModel+Promo.swift`** — replace generic `"Learn more"` label on shared interactive HTML reports with descriptive category text (e.g., `"DeuceMate — Free Tennis Score Tracker"`).

### D. Off-Site Authority, Directories & Community Seeding
- [ ] **[P0] Google Search Console & Bing Webmaster Tools** — verify `https://emrahman.github.io/DeuceMate/` and submit `sitemap.xml` (Bing indexes directly feed ChatGPT Search and Copilot).
- [ ] **[P0] AlternativeTo listing** — list DeuceMate as a Free + Open Source alternative to *SwingVision*, *Tennis Keeper*, *Tiebreak*, *Tennis Math*, and *ScoreAnnouncer*.
- [ ] **[P1] Reddit community posts** — share organic walkthroughs / browser demo (`try.html`) in `r/10s`, `r/AppleWatch`, `r/iosapps`, and `r/padel`.
- [ ] **[P1] Tennis forums** — share on TalkTennis (Tennis Warehouse forums) under Tennis Tips / Equipment & Apps.
- [ ] **[P1] Curated GitHub "Awesome" lists** — open PRs to `awesome-ios`, `awesome-swift`, and `open-source-ios-apps`.
- [ ] **[P2] Hacker News (`Show HN`) & Product Hunt** — highlight the zero-dependency SwiftUI architecture + full browser-based Watch/iPhone simulator (`try.html`).

---

## 2. Baseline Audit (November 2026)

| Surface | What Works Well Now | Key Gaps Holding Back GEO / SEO |
|---------|---------------------|---------------------------------|
| **Website (`docs/website/index.html`)** | Fast static HTML, zero external bloat, rich `alt` attributes on screenshots, strong privacy messaging, interactive browser replica at `try.html`. | `<h1>` (*"Never lose track of the score again."*) omits *"tennis"*, *"Apple Watch"*, and *"score tracker"*. No JSON-LD schema, no `robots.txt`, no `sitemap.xml`, no `llms.txt`, relative 2.1 MB `og:image`, missing v1.2 Trends & v1.3 Head-to-Head features. |
| **Support & Setup (`support.html`, `setup.html`)** | Clear task-oriented headings, semantic `<details>` FAQ blocks, accessible step-by-step structure. | Missing `FAQPage` and `HowTo` JSON-LD schemas; deep reference content in `docs/USER_GUIDE.md` is not published to the website. |
| **GitHub (`README.md`)** | Clear value proposition, App Store badges, screenshots with descriptive captions, architecture transparency. | Does not link to `try.html` (the browser demo); omits v1.2 Performance Trends and v1.3 Opponent Head-to-Head / Match Comparisons / Notes; lacks a structured comparison table. |
| **HTML Match Export (`MatchWebViewModel+Promo.swift`)** | Every shared `.html` match report includes a top `"Tracked with DeuceMate"` banner with App Store and website links. | Website link anchor text is generic (`"Learn more"`), missing an opportunity for descriptive anchor context when reports are shared online. |

---

## 3. Detailed Implementation Specs

### 3.1 `robots.txt` (Host-Root vs. Project Subdirectory on GitHub Pages)
Because `.github/workflows/pages.yml` deploys this repository as a GitHub Pages **project site** at `https://emrahman.github.io/DeuceMate/`, any file placed at `docs/website/robots.txt` is published at `https://emrahman.github.io/DeuceMate/robots.txt`. Under RFC 9309 (Robots Exclusion Protocol) and Google/Bing crawler specifications, `robots.txt` is only discovered at the **origin root** (`https://emrahman.github.io/robots.txt`) and subdirectory `robots.txt` files are ignored.

**Action required:**
1. **Host-root `robots.txt` (`https://emrahman.github.io/robots.txt`):** If the account-level `emrahman.github.io` Pages repository is active, publish the directives below at its root so crawlers discover both the AI bot permissions and `Sitemap: https://emrahman.github.io/DeuceMate/sitemap.xml`.
2. **Direct Sitemap Submission:** Always submit `https://emrahman.github.io/DeuceMate/sitemap.xml` directly in **Google Search Console** (URL-prefix property `https://emrahman.github.io/DeuceMate/`) and **Bing Webmaster Tools** so sitemap discovery does not depend on `robots.txt`.
3. **Project fallback (`docs/website/robots.txt`):** Also commit `docs/website/robots.txt` in this repo so it is immediately active if a custom root domain is ever attached to DeuceMate:

```txt
User-agent: *
Allow: /

# Explicitly welcome AI search and retrieval crawlers
User-agent: OAI-SearchBot
Allow: /

User-agent: GPTBot
Allow: /

User-agent: ChatGPT-User
Allow: /

User-agent: PerplexityBot
Allow: /

User-agent: ClaudeBot
Allow: /

User-agent: Claude-Web
Allow: /

User-agent: Google-Extended
Allow: /

User-agent: Applebot-Extended
Allow: /

Sitemap: https://emrahman.github.io/DeuceMate/sitemap.xml
```

### 3.2 `docs/website/sitemap.xml`
Create `docs/website/sitemap.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://emrahman.github.io/DeuceMate/</loc>
    <lastmod>2026-11-03</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>https://emrahman.github.io/DeuceMate/try.html</loc>
    <lastmod>2026-11-03</lastmod>
    <changefreq>weekly</changefreq>
    <priority>0.9</priority>
  </url>
  <url>
    <loc>https://emrahman.github.io/DeuceMate/setup.html</loc>
    <lastmod>2026-11-03</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://emrahman.github.io/DeuceMate/support.html</loc>
    <lastmod>2026-11-03</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
  <url>
    <loc>https://emrahman.github.io/DeuceMate/privacy.html</loc>
    <lastmod>2026-11-03</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.5</priority>
  </url>
</urlset>
```

### 3.3 `docs/website/llms.txt`
Create `docs/website/llms.txt` following the standard `llms.txt` specification so LLM agents inspecting the domain root get an authoritative, hallucination-proof overview:

```markdown
# DeuceMate

> DeuceMate is a 100% free, open-source, privacy-first tennis and padel score tracker app for Apple Watch and iPhone. It combines gesture-first on-wrist live scoring with an iPhone companion for live scoreboards, spoken umpire announcements, 20+ match statistics, cross-match performance trends, head-to-head opponent records, HealthKit heart-rate zone analytics (PulseCoach), one-tap AI coaching prompts (for ChatGPT, Claude, and Gemini), and self-contained offline HTML match reports.

## Key Facts
- **Category:** Tennis Score Tracker / Tennis Score Keeper / Sports Analytics App
- **Platforms:** Apple Watch (watchOS 9.0+, Series 4, SE, Ultra or newer) + iPhone (iOS 17.0+)
- **Price:** Free forever ($0 — no subscriptions, no in-app purchases, no ads)
- **License:** MIT Open Source (100% native SwiftUI, zero third-party SDKs)
- **Privacy:** Zero developer data collection, no account required, works offline, peer-to-peer WatchConnectivity sync, optional personal iCloud Drive backup (with HealthKit data stripped).
- **App Store:** https://apps.apple.com/app/id6757105622
- **Website:** https://emrahman.github.io/DeuceMate/
- **Interactive Browser Demo:** https://emrahman.github.io/DeuceMate/try.html
- **GitHub Repository:** https://github.com/EMRahman/DeuceMate

## Core Capabilities
1. **Gesture-First Apple Watch Scoring:** Swipe up (win point), swipe down (lose point), swipe left (infinite undo across games/sets), swipe right (live stats), double-tap (2nd serve).
2. **Full Tennis & Padel Rules:** 6 match formats (Best of 3 with 10-pt super tiebreak, Best of 3 full final set, single Super Tiebreak, Perpetual Super Tiebreak, Quick 4 Games, Perpetual Points). Singles and doubles with automatic 4-player service rotation, break-point detection, sticky changeover reminders, and a GPS-free watch compass court-end indicator.
3. **iPhone Companion & No-Watch Mode:** Real-time stadium scoreboard, spoken umpire announcements, optional court-side iPhone scoring input, and manual match entry (usable even without an Apple Watch).
4. **Deep Match Analytics (20+ Stats):** Serve/return percentages, winners, unforced/forced errors, W:UE ratio, break-point conversion/save rates, rally depth (serve, return, serve+1, 4+ rally), and interactive points-momentum charts filterable by set.
5. **Cross-Match Performance Trends & Head-to-Head Records:** Track metric trends across match history (including set-by-set fatigue and steps per point) and maintain an opponent directory with singles/doubles head-to-head records, playing styles, match comparisons, and private match notes.
6. **RecCoach, PulseCoach & AI Coach Exports:** Rule-based coaching insights, heart-rate zone win percentages via Apple HealthKit, one-tap structured prompt generation for ChatGPT/Claude/Gemini (for either player's perspective), and single-file interactive `.html` match exports.

## Documentation Links
- [Overview & Features](https://emrahman.github.io/DeuceMate/): Main product overview and FAQ
- [Interactive Browser Simulator](https://emrahman.github.io/DeuceMate/try.html): Try both the Apple Watch and iPhone apps directly in the browser
- [Step-by-Step Setup Guide](https://emrahman.github.io/DeuceMate/setup.html): Visual guide from App Store install to scoring a match
- [Support & Troubleshooting](https://emrahman.github.io/DeuceMate/support.html): Getting started, sync diagnostics, backup/restore, and extended FAQ
- [Privacy Policy](https://emrahman.github.io/DeuceMate/privacy.html): Data handling and HealthKit privacy details
- [Source Code & User Guide](https://github.com/EMRahman/DeuceMate): Full SwiftUI source code and user guide
```

### 3.4 Schema.org JSON-LD for `docs/website/index.html`
Embed inside `<head>` in `docs/website/index.html`:

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": ["MobileApplication", "SoftwareApplication"],
      "name": "DeuceMate",
      "alternateName": "DeuceMate Tennis Score Keeper + Stats",
      "description": "Free, open-source tennis and padel score tracker app for Apple Watch and iPhone. Track live points, games, sets, and tiebreaks on your wrist, hear umpire score announcements, analyze 20+ match stats and cross-match trends, track head-to-head opponent records, and export one-tap AI coaching prompts.",
      "applicationCategory": "SportsApplication",
      "operatingSystem": "iOS 17.0+, watchOS 9.0+",
      "url": "https://emrahman.github.io/DeuceMate/",
      "downloadUrl": "https://apps.apple.com/app/id6757105622",
      "installUrl": "https://apps.apple.com/app/id6757105622",
      "codeRepository": "https://github.com/EMRahman/DeuceMate",
      "license": "https://opensource.org/licenses/MIT",
      "isAccessibleForFree": true,
      "offers": {
        "@type": "Offer",
        "price": "0",
        "priceCurrency": "USD"
      },
      "author": {
        "@type": "Person",
        "name": "Ehsan Rahman",
        "url": "https://ehsanrahman.com"
      },
      "sameAs": [
        "https://apps.apple.com/app/id6757105622",
        "https://github.com/EMRahman/DeuceMate"
      ]
    }
  ]
}
</script>
```
*(Also include a `"@type": "FAQPage"` node in the `@graph` matching the visible FAQ questions on `index.html` and `support.html`.)*

### 3.5 Title, Heading & Copy Upgrades (`docs/website/index.html`)

| Element | Current (`docs/website/index.html`) | Recommended Update |
|---------|-------------------------------------|--------------------|
| `<title>` | `DeuceMate — Tennis scoring, live on your wrist. Coaching, from your data.` | `DeuceMate — Free Tennis Score Tracker & Keeper App for Apple Watch & iPhone` |
| `<meta name="description">` | `Now on the App Store — free. DeuceMate keeps score on your Apple Watch, mirrors it live on your iPhone, and turns every match into 20+ stats and one-tap AI coaching. No ads. No tracking.` | `Free, open-source tennis and padel score tracker for Apple Watch and iPhone. Swipe to score on your wrist, hear live umpire announcements, track 20+ match stats, head-to-head records, and get one-tap AI coaching. No ads, no subscriptions.` |
| Hero Eyebrow | `🎾 Now on the App Store — free, for club & recreational players` | `🎾 Free, Open-Source Tennis & Padel Score Tracker for Apple Watch & iPhone` |
| `<h1>` | `Never lose track of the score again.` | `Never lose track of the tennis score again.` *(or pair with a semantic subheading containing "Apple Watch tennis score keeper & match tracker")* |

### 3.6 Comparison Table for GEO Citability (`index.html` & `README.md`)
LLMs answering *"What is the best tennis score tracker app?"* look for side-by-side feature matrices. Adding a concise comparison table gives retrieval models pre-structured facts:

| Feature | DeuceMate | Typical Tennis Score Apps | Built-in Watch Workout |
|---------|-----------|---------------------------|------------------------|
| **Price** | **100% Free (No ads, no IAP)** | $20–$150/yr subscription or ads | Free |
| **Apple Watch Live Scoring** | **Swipe gestures + full undo stack** | Often tap-heavy or phone-only | No score tracking |
| **Doubles & Padel Support** | **Full 4-player server rotation & padel** | Often limited or paid add-on | Workout timer only |
| **Match Stats & Momentum Graph** | **20+ stats, rally depth, HR overlays** | Basic or paywalled | Heart rate & calories only |
| **Trends & Head-to-Head Records** | **Included (Trends, H2H, Match Compare)** | Rarely included / paywalled | None |
| **AI Coaching (ChatGPT/Claude/Gemini)** | **1-tap structured prompt + raw points** | None | None |
| **Shareable Web Match Report** | **Self-contained offline `.html` file** | Requires recipient to install app | None |
| **Privacy & Open Source** | **MIT Open Source · 0 data collected** | Closed source · analytics/trackers | Apple Health |

---

## 4. Ongoing GEO Benchmark Log (How to Measure Marketing Success)

Because LLM outputs are non-deterministic and evolve with search indexes, run the following **5 benchmark prompts** once a month in **ChatGPT (with Search enabled)**, **Perplexity**, **Claude (with Web Search)**, and **Google Search / AI Overviews** in an incognito/fresh session.

### Standard Benchmark Prompts
1. **Category Head Query:** *"What is the best tennis score tracker app for Apple Watch?"*
2. **Free / No-Subscription Query:** *"Can you recommend a free tennis score keeper app for Apple Watch and iPhone with no subscription or ads?"*
3. **Analytics & AI Query:** *"Which tennis scoring app lets me track match stats on Apple Watch and export my match data to ChatGPT or Claude for coaching?"*
4. **Privacy / Open-Source Query:** *"Are there any open-source or privacy-focused tennis score tracker apps for iOS and watchOS?"*
5. **Padel / Doubles Query:** *"What is a good Apple Watch app for keeping score in doubles tennis or padel that tracks server rotation?"*

### Monthly Tracking Log

| Date | Engine / Model | Prompt # | Recommended? (Yes / Mentioned / No) | Rank Position | Cited URLs (GitHub, Website, Reddit, App Store, etc.) | Notes / Action Taken |
|------|----------------|----------|-------------------------------------|---------------|-------------------------------------------------------|----------------------|
| 2026-11-03 | ChatGPT Search | 1–5 | *Baseline (pre-GEO)* | — | — | Initial audit created |
| 2026-11-03 | Perplexity | 1–5 | *Baseline (pre-GEO)* | — | — | Initial audit created |
| 2026-11-03 | Claude Web | 1–5 | *Baseline (pre-GEO)* | — | — | Initial audit created |
| 2026-11-03 | Google AI Overview | 1–5 | *Baseline (pre-GEO)* | — | — | Initial audit created |
