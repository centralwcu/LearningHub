# Learning Hub Migration Plan

## Overview

Migrate the Learning Hub from iframe-embedded Scribe guides to self-hosted HTML guide pages. Each guide becomes its own HTML page with centralized CSS. An automated PowerShell script handles converting Scribe guides to local HTML.

---
## Current State

- **Single-page site** (index.html) with all CSS/JS inline
- **~40 guides** loaded via iframe from scribehow.com
- **Fullscreen overlay** displays guides on top of the hub
- **Features**: search, favorites (with drag reorder), collapsible sections, mobile-responsive layout
- **Hosting**: GitHub Pages

---
## Target State

- **Hub page** (index.html) links directly to local guide pages (no overlay, no iframes)
- **Individual guide pages** in guides/ directory
- **Centralized CSS/JS** shared between hub and guide pages
- **PowerShell conversion script** to generate guide HTML from Scribe URLs
- **Config-driven** guide list for easy additions and updates

---
## Architecture

```plaintext
LearningHub/
├── index.html                     # Hub page (guide directory)
├── css/
│   ├── hub.css                    # Hub-specific styles
│   └── guide.css                  # Shared guide page styles
├── js/
│   └── hub.js                     # Hub functionality (search, favorites, etc.)
├── images/
│   ├── CWlogo.png
│   └── guides/                    # Downloaded guide screenshots
├── guides/
│   ├── online/
│   │   ├── open-account.html
│   │   ├── send-money-person.html
│   │   ├── online-banking-tour.html
│   │   └── ...
│   └── mobile/
│       ├── mobile-deposit.html
│       ├── bill-pay.html
│       └── ...
└── tools/
    ├── convert-guides.ps1         # Main conversion script
    ├── guide-config.json          # Guide URLs and metadata
    └── guide-template.html        # HTML template for generated guides
```

---
## Phase 1: Design & Build Sample Guide Pages

Create a few guide pages manually by converting Scribe guides to HTML. Iterate on the design until the look and feel is right. These samples establish the patterns and design language for all guides.
- Convert 3-4 diverse guides (varying lengths, content types)
- Refine layout, typography, step cards, image handling, warnings/info blocks
- Ensure responsive design works on mobile and desktop
- Add "Back to Learning Hub" navigation

### Back to Learning Hub Nav Bar (established pattern)

Every guide page must include a sticky top nav bar as the **first element inside `<body>`**, before the `.container` div:

```html
<nav class="guide-topnav">
    <a href="../index.html">
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"></polyline></svg>
        Back to All Guides
    </a>
</nav>
```

Since Phase 2, guide CSS is in `css/guide.css` (linked via `<link rel="stylesheet" href="../../css/guide.css">`). Do **not** include a `<style>` block in guide pages — all styles are inherited from `guide.css`.

The back button `href` must be `../../index.html` (guides live two levels deep at `guides/mobile/`).

### Linking a Converted Guide in index.html

When adding a converted guide to both Mobile Banking lists in `index.html`, use an `<a>` tag with class `btn btn-link text-decoration-none p-0` and a `data-keywords` attribute. **Do not use `<button>`** — the favorite star logic in `hub.js` targets `a.btn` for local guides.

```html
<li class="list-group-item">
  <a class="btn btn-link text-decoration-none p-0" href="guides/mobile/your-guide-slug.html"
    data-keywords="keyword1, keyword2, ...">
    Guide Title
  </a>
</li>
```

With the following CSS included in the guide's `<style>` block (legacy reference only — new guides use `guide.css`):

```css
.guide-topnav {
    position: sticky;
    top: 0;
    z-index: 100;
    background-color: #ed5f2d;
    display: flex;
    align-items: center;
    padding: 0 24px;
    height: 52px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.15);
}

.guide-topnav a {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    color: #fff;
    font-weight: 600;
    font-size: 0.95em;
    line-height: 1;
    text-decoration: none;
    opacity: 0.95;
    transition: opacity 0.15s;
}

.guide-topnav a:hover {
    opacity: 1;
    text-decoration: none;
}

.guide-topnav svg {
    flex-shrink: 0;
    position: relative;
    top: 2px;
}
```

> **Note**: The `href` path (`../index.html`) assumes the guide file lives one directory below the hub root (e.g., `guides/mobile/`). Update the path if the guide is in a different location.

---
## Phase 2: Centralize CSS/JS & Integrate into Hub ✅ COMPLETE

- Extracted guide styles into `css/guide.css`
- Extracted hub styles into `css/hub.css`
- Extracted hub scripts into `js/hub.js`
- Updated all converted guide pages to link to `css/guide.css`
- **Removed the iframe overlay system entirely** — no more ScribeHow iframes in the hub
- Converted guides use `<a class="btn btn-link ...">` direct links; unconverted guides show as `<span class="guide-pending">` (greyed-out, not clickable)
- Search works across both converted (`a.btn`) and pending (`span.guide-pending`) items via `data-keywords`
- Favorites only apply to converted (local) guides
- All unconverted guide data preserved in `Working/guides-to-convert.json`

### Guide Queue File: `Working/guides-to-convert.json`

This file is the **single source of truth** for all guides still to be converted. For each guide it stores:
- `title` — display name used in `index.html`
- `outputFile` — where the converted HTML should be saved (e.g., `guides/mobile/send-money-to-person.html`)
- `scribeUrl` — the ScribeHow URL to fetch content from when running the conversion script
- `keywords` — the `data-keywords` value to use in `index.html`

**When a guide is converted**, do the following in `index.html` (both the desktop section and its matching mobile-only section):

1. Find the `<span class="guide-pending" data-keywords="...">Title</span>` for that guide
2. Replace it with an `<a>` tag:
```html
<li class="list-group-item">
  <a class="btn btn-link text-decoration-none p-0" href="guides/mobile/your-guide-slug.html"
    data-keywords="keyword1, keyword2, ...">
    Guide Title
  </a>
</li>
```
3. Remove the guide's entry from `Working/guides-to-convert.json`

---
## Phase 3: Build Conversion Script

With the design locked and the hub ready, build a PowerShell script to automate guide conversion from ScribeHow.

### Approach: PowerShell + Edge Headless (`Start-Process` method)

ScribeHow pages render content with JavaScript. Use **Microsoft Edge's built-in headless mode** via `Start-Process` with `RedirectStandardOutput` to capture the fully-rendered DOM (the `& $edge` call syntax does **not** work — must use `Start-Process`):

```powershell
$pinfo = New-Object System.Diagnostics.ProcessStartInfo
$pinfo.FileName               = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
$pinfo.Arguments              = "--headless --disable-gpu --dump-dom `"$url`""
$pinfo.RedirectStandardOutput = $true
$pinfo.RedirectStandardError  = $true
$pinfo.UseShellExecute        = $false
$proc = [System.Diagnostics.Process]::Start($pinfo)
$dom  = $proc.StandardOutput.ReadToEnd()
$proc.WaitForExit()
```

Use the `/viewer/{ScribeId}` URL (not `/shared/` or `/embed-preview/`). This returns ~190KB of rendered HTML containing all step content with `data-testid="action-instruction"` markers.

> **Important**: ScribeHow step images use **signed S3 URLs** that expire in ~15 minutes. Download them immediately after fetching the DOM.

### Input: `Working/guides-to-convert.json`

The script reads from `Working/guides-to-convert.json` — all guide metadata (title, scribeUrl, outputFile, keywords) is already captured there. No separate config file needed.

### Script design (`tools/convert-guide.ps1`)

```plaintext
Input:  Working/guides-to-convert.json entry (by title or outputFile)
Output: HTML file at outputFile path + images at images/guides/{slug}/
```

**Steps per guide:**
1. **Fetch** rendered HTML from `/viewer/{ScribeId}` via Edge headless (`Start-Process` method above)
2. **Parse** the DOM to extract:
   - Title: `data-testid="document-title"`
   - Description: element with class `whitespace-pre-wrap`
   - Steps: `data-testid="action-instruction"` blocks — each contains step number, text, optional image
   - Warning/tip cards: `data-testid="action-tip-or-warning"` blocks
3. **Download** images immediately (signed URLs expire ~15 min):
   - Save as `step-01.webp`, `step-02.webp`, etc.
   - Directory: `images/guides/{slug}/` (slug derived from `outputFile`)
4. **Generate** HTML from the established template (see Phase 1 pattern)
5. **Write** output to the `outputFile` path from `guides-to-convert.json`

### CLI usage

```plaintext
# Convert a single guide (match by title keyword)
.\tools\convert-guide.ps1 -Title "Mobile Deposit"

# Convert all guides in the queue
.\tools\convert-guide.ps1 -All
```

### Template

Follow the exact HTML structure of existing converted guides (`guides/mobile/making-a-mobile-deposit.html`). Key requirements:
- Link to `../../css/guide.css` (guides live two levels deep)
- Back button `href` is `../../index.html`
- Back button text is **"Back to All Guides"**
- Image paths: `../../images/guides/{slug}/step-XX.webp`

---
## Phase 4: Full Migration & Deployment

- Run the script to generate all remaining guide pages
- Verify each guide renders correctly
- Finalize all links in index.html
- Test search, favorites, and navigation end-to-end
- Commit and push to GitHub Pages

---
## Ongoing Maintenance


|        Task         |                                     Steps                                      |
|---------------------|--------------------------------------------------------------------------------|
| **Update a guide**  | Edit on Scribe → run script for that guide → commit, push                      |
| **Add a new guide** | Create on Scribe → add to config → add link in hub → run script → commit, push |
| **Redesign guides** | Update `guide.css` and/or template → run script for all → commit, push         |


---
## Key Decisions


|    Decision     |           Choice            |                Rationale                 |
|-----------------|-----------------------------|------------------------------------------|
| Guide display   | Separate pages (no overlay) | Simpler, better URLs, native back button |
| Script language | PowerShell                  | No additional installs on Windows        |
| Web scraping    | Edge headless `--dump-dom`  | Built into Windows, handles JS rendering |
| Image hosting   | Download locally            | No external dependencies                 |
| Image handling  | Use signed URLs from page   | ScribeHow requires authentication tokens |
| CSS approach    | Centralized `guide.css`     | One file to update for all guides        |
| Mobile/desktop  | Single guide file for both  | Eliminates current duplication           |

