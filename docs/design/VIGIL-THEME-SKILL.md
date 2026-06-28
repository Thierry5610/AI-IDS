---
name: vigil-dark-console-theme
description: Use this skill to reproduce the exact "VIGIL" visual identity — a specific dark-glass, lime-accent, circular-badge dashboard theme — built for this user across the Overview, Incidents, Threats, and Assets pages. Trigger when the person says "use the VIGIL look," "match my dashboard demo," "same style as before," "build another page like this," or references this theme by name or by describing lime/black/glass/circular dashboard. This is a concrete drop-in theme with exact tokens, exact CSS, and exact icon markup — not general guidance. For the broader genre principles this theme is one instance of, see the bento-dashboard-ui skill instead.
---

# VIGIL — dark console theme

A self-contained visual system: true-black base, one confident acid-lime accent, circular icon badges and pill buttons throughout, ambient color-glow behind frosted glass cards, Space Grotesk for numbers, Inter for everything else, JetBrains Mono for literal data. Four pages exist already (Overview, Incidents, Threats, Assets) sharing one rail, one topbar, one card treatment, and one token set — any new page should slot into that same shell.

## Fonts

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600;700&family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
```

## Tokens (copy verbatim)

```css
:root{
  --bg:#070707; --surface:#0e0e0e; --surface-2:#161616;
  --glass-bg:rgba(20,21,18,0.5); --glass-bg-2:rgba(255,255,255,0.04);
  --border:rgba(255,255,255,0.08); --border-strong:rgba(255,255,255,0.16);
  --text:#f3f3ef; --muted:#9a9a93; --muted-2:#5c5c56;
  --lime:#d4ff3d; --lime-dim:rgba(212,255,61,0.14);
  --cyan:#3de8ff; --violet:#b26eff;
  --green:#34d399; --green-soft:rgba(52,211,153,0.14);
  --amber:#ffb020; --amber-soft:rgba(255,176,32,0.14);
  --red:#ff4d5e; --red-soft:rgba(255,77,94,0.14);
  --r-lg:16px; --r-md:12px; --r-sm:9px;
  --f-display:'Space Grotesk',sans-serif; --f-body:'Inter',sans-serif; --f-mono:'JetBrains Mono',monospace;
}
svg{stroke-width:2;}
```

Color rules: `--lime` is the only branding accent — used as icon tints, chart strokes, and exactly one full solid KPI block per page. `--cyan` and `--violet` are categorical chart colors only (bubble clusters, multi-series lists) — never UI chrome. `--green`/`--amber`/`--red` are status only, always as a small pill, never a fill.

## Ambient glow + glass body

```css
html,body{
  background:
    radial-gradient(620px circle at 10% 15%, rgba(212,255,61,0.09), transparent 60%),
    radial-gradient(680px circle at 90% 10%, rgba(61,232,255,0.07), transparent 60%),
    radial-gradient(720px circle at 75% 90%, rgba(178,110,255,0.08), transparent 60%),
    radial-gradient(500px circle at 20% 85%, rgba(212,255,61,0.05), transparent 60%),
    var(--bg);
  background-attachment:fixed; min-height:100vh;
}
```

## Shell layout (use on every page, unchanged)

```html
<div class="app">
  <aside class="rail"> <!-- logo + nav icons + settings + status dot --> </aside>
  <div class="main">
    <header class="topbar"> <!-- brand + page title + actions --> </header>
    <div class="content"><div class="bento"> <!-- page-specific cards --> </div></div>
  </div>
</div>
```

```css
.app{display:flex;min-height:100vh;}
.rail{width:64px;flex-shrink:0;background:rgba(14,14,14,0.65);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);
  border-right:1px solid var(--border);display:flex;flex-direction:column;align-items:center;padding:18px 0;
  position:sticky;top:0;height:100vh;}
.rail-item{position:relative;width:38px;height:38px;border-radius:50%;display:flex;align-items:center;justify-content:center;
  color:var(--muted-2);}
.rail-item.active{color:var(--lime);background:var(--lime-dim);}
.rail-item.active::before{content:'';position:absolute;left:-12px;top:50%;transform:translateY(-50%);
  width:4px;height:16px;border-radius:3px;background:var(--lime);}
.topbar{height:62px;display:flex;align-items:center;gap:14px;padding:0 24px;border-bottom:1px solid var(--border);
  position:sticky;top:0;z-index:5;background:rgba(7,7,7,0.55);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);}
.content{padding:24px 26px 40px;max-width:1380px;width:100%;margin:0 auto;}
.bento{display:flex;flex-direction:column;gap:18px;}
```

Set `tb-title` to the current page name and add `active` (plus `aria-current="page"`) to the matching `.rail-item` — every other rail/topbar attribute stays identical across pages.

## Card / glass treatment (every card on every page)

```css
.card{background:var(--glass-bg);backdrop-filter:blur(18px) saturate(140%);-webkit-backdrop-filter:blur(18px) saturate(140%);
  border:1px solid var(--border-strong);border-radius:var(--r-lg);padding:18px 18px 16px;
  box-shadow:inset 0 1px 0 rgba(255,255,255,0.05), 0 10px 28px -16px rgba(0,0,0,0.6);}
```

The one exception: `.kpi.featured` (the hero KPI) stays fully opaque solid lime, no blur:
```css
.kpi.featured{background:var(--lime);backdrop-filter:none;-webkit-backdrop-filter:none;border-color:var(--lime);
  animation:lime-pulse 2.6s ease-in-out infinite;}
.kpi.featured .kpi-value, .kpi.featured .kpi-label{color:#0a0a0a;}
@keyframes lime-pulse{0%,100%{box-shadow:0 0 0 0 rgba(212,255,61,0);}50%{box-shadow:0 0 18px 1px rgba(212,255,61,0.4);}}
```

## Logo mark (identical on every page)

```html
<svg class="rail-logo" viewBox="0 0 32 32" fill="none">
  <circle cx="16" cy="16" r="12.5" stroke="var(--lime)" stroke-width="2"/>
  <circle cx="16" cy="16" r="5.5" fill="var(--lime)"/>
  <line x1="16" y1="2.5" x2="16" y2="7.5" stroke="var(--lime)" stroke-width="2" stroke-linecap="round" opacity="0.55"/>
</svg>
```
A circular eye/orb with a radar-sweep tick — never the discarded faceted-diamond version from an earlier draft.

## Icon library (24x24 viewBox, stroke-width 2, round caps/joins — copy any of these directly)

```
Overview/bento  : <rect x="3" y="3" width="9" height="9" rx="2"/><rect x="14" y="3" width="7" height="4" rx="1.6"/><rect x="14" y="9" width="7" height="3" rx="1.4"/><rect x="3" y="14" width="18" height="7" rx="2"/>
Incidents/alert : <circle cx="12" cy="12" r="8.5"/><line x1="12" y1="8" x2="12" y2="13"/><circle cx="12" cy="16.3" r="0.5" fill="currentColor" stroke="none"/>
Threats/radar   : <circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.6" fill="currentColor" stroke="none" opacity="0.18"/><circle cx="12" cy="12" r="3.6"/><circle cx="12" cy="12" r="0.6" fill="currentColor" stroke="none"/>
Assets/tag      : <path d="M4 4h7l9 9-7 7-9-9V4z"/><circle cx="8" cy="8" r="1.4" fill="currentColor" stroke="none"/>
Network/nodes   : <line x1="6.7" y1="7.3" x2="10.6" y2="11.7"/><line x1="17.3" y1="7.3" x2="13.4" y2="11.7"/><line x1="11" y1="14.5" x2="7" y2="17.7"/><line x1="13" y1="14.5" x2="17" y2="17.7"/><circle cx="5" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="19" cy="6" r="2.1" fill="currentColor" stroke="none"/><circle cx="12" cy="13" r="2.3" fill="currentColor" stroke="none"/><circle cx="6" cy="19" r="2.1" fill="currentColor" stroke="none"/><circle cx="18" cy="19" r="2.1" fill="currentColor" stroke="none"/>
Reports/doc     : <rect x="5" y="3" width="14" height="18" rx="2"/><rect x="8" y="13" width="2" height="5" fill="currentColor" stroke="none"/><rect x="11.3" y="10" width="2" height="8" fill="currentColor" stroke="none"/><rect x="14.6" y="7" width="2" height="11" fill="currentColor" stroke="none"/>
Settings/slider : <line x1="4" y1="7" x2="20" y2="7"/><circle cx="9" cy="7" r="2.1" fill="var(--surface)"/><line x1="4" y1="12.5" x2="20" y2="12.5"/><circle cx="16" cy="12.5" r="2.1" fill="var(--surface)"/><line x1="4" y1="18" x2="20" y2="18"/><circle cx="12" cy="18" r="2.1" fill="var(--surface)"/>
Search          : <circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.5" y2="16.5"/>
Bell            : <path d="M18 8a6 6 0 10-12 0c0 4-2 5-2 6h16c0-1-2-2-2-6z"/><path d="M10 19a2 2 0 004 0"/>
Clock           : <circle cx="12" cy="12" r="8"/><path d="M12 7.5V12l3 2"/>
Triangle alert  : <path d="M12 3l9.5 16.5h-19L12 3z"/><line x1="12" y1="9.5" x2="12" y2="14"/>
Check           : <path d="M6 12l4 4 8-9"/>
Cloud           : <path d="M7 17a4 4 0 010-8 5 5 0 019.6-1.5A4.5 4.5 0 0117 17H7z"/>
Key/identity    : <circle cx="8" cy="8" r="4"/><path d="M11 11l8 8M16 16l3-3"/>
Chevron down    : <path d="M6 9l6 6 6-6"/>
```

Settings' two `fill="var(--surface)"` handle-knockouts assume the icon sits on `var(--surface)` (true in the rail) — if reused somewhere with a different background behind it, swap that fill to match.

## Component recipes

**KPI row** — 4 cards, first one `.kpi.featured` (solid lime, see above), the rest:
```css
.kpi-icon{width:32px;height:32px;border-radius:50%;border:1px solid var(--border-strong);background:var(--glass-bg-2);
  display:flex;align-items:center;justify-content:center;color:var(--muted);}
.kpi-value{font-family:var(--f-display);font-size:32px;font-weight:600;letter-spacing:-0.5px;}
.delta{font-size:11px;font-weight:600;padding:3px 9px;border-radius:99px;}
.delta.good{color:var(--green);background:var(--green-soft);} .delta.bad{color:var(--amber);background:var(--amber-soft);}
```
No sparklines — this theme deliberately omits them for a cleaner KPI block.

**Avatar** (topbar + table person cells) — always this, never a gradient:
```css
.avatar{width:26px;height:26px;border-radius:50%;background:var(--surface-2);border:1px solid var(--border-strong);
  display:flex;align-items:center;justify-content:center;font-family:var(--f-display);font-size:10px;font-weight:700;color:var(--lime);}
```

**Incident/event log stream**: vertical list, circular icon per row connected by a thin line, mono metadata. Severity = icon color only (red/amber/green), never a background wash:
```css
.log-icon{width:22px;height:22px;border-radius:50%;background:var(--glass-bg-2);border:1px solid var(--border-strong);}
.log-icon.crit{color:var(--red);} .log-icon.warn{color:var(--amber);} .log-icon.ok{color:var(--green);}
.log-line{width:1px;flex:1;background:var(--border-strong);min-height:18px;}
```

**AI Suggested Actions**: text + two pill buttons, `.ai-btn.approve` solid lime, `.ai-btn.reject` ghost/muted. On click, fade the row to 0.35 opacity and disable both buttons (see Overview page script for the exact handler).

**Threat-coverage radar** (8-axis polygon, reuse these exact precomputed coordinates for an octagon centered at 110,110 with outer radius 85 — recompute only if you need a different axis count):
```
Outer ring: 110,25 170.1,49.9 195,110 170.1,170.1 110,195 49.9,170.1 25,110 49.9,49.9
Mid ring (65%): 110,54 149.6,70.4 166,110 149.6,149.6 110,166 70.4,149.6 54,110 70.4,70.4
Inner ring (33%): 110,82 129.8,90.2 138,110 129.8,129.8 110,138 90.2,129.8 82,110 90.2,90.2
Data polygon fill: fill-opacity 0.16, stroke var(--lime), stroke-width 1.8
```
General formula for N axes: angle per axis = -90° + i·(360/N)°; point = (cx + r·cos(θ), cy + r·sin(θ)).

**Packed bubble cluster** (replaces a donut): 5 columns of 3 circles each, decreasing radius, colors cycling through lime/cyan/violet/off-white, labels centered below each column at `text-anchor: middle`. See Overview "Attack Surface by Vector" or Assets "Asset Type Breakdown" for the exact coordinate sets — reuse the column x-positions (40/100/160/220/280 in a 320-wide viewBox) and just relabel.

**Trend chart with glow** (no hatch fill — see anti-pattern in the genre skill):
```
<linearGradient> top stop-opacity 0.35 lime → bottom stop-opacity 0
<filter><feGaussianBlur stdDeviation="3.5"/></filter>  — apply to a 5px-wide, 0.4-opacity duplicate of the line for the glow
crisp line on top: stroke-width 2.2, round caps
dashed vertical marker at the peak point, stroke var(--border-strong), stroke-dasharray "3 4"
.float-tip: rounded-rect tooltip (not a pill), two lines — bold mono value + muted label, anchored via
  transform: translate(-50%,-118%) at the peak point's percentage position
```

**Logo-chain / connected sources strip**:
```css
.strip-row{position:relative;} 
.strip-row::before{content:'';position:absolute;left:22px;right:22px;top:50%;height:1px;
  background-image:repeating-linear-gradient(90deg,var(--border-strong) 0 4px,transparent 4px 8px);}
.strip-icon{width:30px;height:30px;border-radius:50%;background:var(--glass-bg-2);border:1px solid var(--border-strong);}
.strip-more{/* same circular size */ border:1px dashed var(--border-strong);font-family:var(--f-mono);}
```

**ATT&CK-style heatmap matrix** (Threats page): `grid-template-columns: 130px repeat(8,1fr)`, square cells (`aspect-ratio:1`, `border-radius:4px`), 4 discrete intensity classes:
```css
.hm-cell.i1{background:rgba(212,255,61,0.15);} .hm-cell.i2{background:rgba(212,255,61,0.35);}
.hm-cell.i3{background:rgba(212,255,61,0.6);}  .hm-cell.i4{background:rgba(212,255,61,0.9);}
```

**Search/filter toolbar + pagination** (Incidents, Assets pages): pill search box with leading icon, pill filter toggles (`.filter-pill.active` = solid lime), a `.btn-primary` pill on the far right, and below the table a `.pagination` row with muted "Showing X–Y of Z" text plus two circular `.pg-btn` prev/next buttons — see either page's CSS block verbatim, it's fully reusable as-is.

**Data table**: uppercase muted header, hairline row borders (no zebra), mono font for IPs/IDs/timestamps, `.pill` for severity/status (critical/high/medium/low/open/investigating/resolved/online/offline classes already defined across the Incidents and Assets pages — reuse those exact class names for consistency).

## Extending to a new page

1. Copy the full `<head>` block, `:root` tokens, shell layout, rail (with the correct `.active` item swapped), and topbar verbatim from any existing VIGIL page.
2. Reuse existing component CSS for anything that matches an existing pattern (KPI row, table, log stream, bubble cluster, etc.) rather than rewriting it.
3. Only invent new CSS for a genuinely new component, and when you do, follow the rules in the bento-dashboard-ui skill (circular badges, pill buttons, glass cards, no hatch fill, no second shape language) so it still reads as VIGIL.
4. Add the new page's nav icon to the rail on every other existing page too, so the nav stays identical across the whole product.
