# Intelligent Dashboard HTML Mock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a branded, self-contained ChickMark HTML dashboard mock that combines executive status, operational triage, root-cause analysis, and data-aware per-sector comparisons.

**Architecture:** Keep the deliverable in one offline HTML file with embedded fixture data, CSS, SVG chart rendering, and interaction logic. A focused Playwright test file drives the build through public DOM behavior and verifies filtering, insight drill-down, snapshot-versus-BMK bars, cumulative sample lines, dense-selection fallback, accessibility, responsiveness, and network isolation.

**Tech Stack:** Semantic HTML5, CSS custom properties, vanilla JavaScript, inline SVG, Node.js built-in test runner, bundled Playwright package, installed Google Chrome.

## Global Constraints

- Primary product references are the current Flutter dashboard code and `docs/LIVING_SPEC.md`.
- Deliver exactly one runnable artifact at `prototypes/dashboard_v6_intelligence.html`; test and plan files are support artifacts.
- Use fixture data and label it visibly as fixture data.
- Use ChickMark brand colors and 10px card/control radii from `AppColors` and `AppSizes`.
- Keep the file offline and self-contained: no CDN, remote font, remote icon, image, script, stylesheet, fetch, or sibling runtime data.
- Do not modify Flutter application behavior.
- Preserve existing unrelated local changes.
- Snapshot mode supports up to six sample bars against BMK.
- Cumulative mode shows up to four selected sample lines plus BMK; five or more selected samples switch to Pool plus min–max range and an outlier ranking.
- Sector controls expose only hierarchy layers supported by that sector fixture.
- The prototype must not present hypotheses as veterinary certainty.
- `docs/LIVING_SPEC.md` remains unchanged because this prototype does not change implemented Flutter behavior.

---

## File Structure

- Create `prototypes/dashboard_v6_intelligence.html`
  - Owns fixture data, application state, semantic markup, branded styles, rendering functions, inline SVG charts, and interactions.
- Create `test/prototypes/dashboard_v6_intelligence_test.mjs`
  - Owns browser acceptance coverage for the standalone prototype.
- Create `docs/superpowers/plans/2026-07-23-intelligent-dashboard-html-mock.md`
  - Owns this execution checklist.

The production artifact stays intentionally single-file. JavaScript is organized inside the file by responsibility: fixture constants, state/derivations, renderers, event handlers, and bootstrapping.

---

### Task 1: Acceptance Harness And Branded Dashboard Shell

**Files:**
- Create: `test/prototypes/dashboard_v6_intelligence_test.mjs`
- Create: `prototypes/dashboard_v6_intelligence.html`

**Interfaces:**
- Consumes: bundled `playwright` package through `NODE_PATH`.
- Produces: semantic landmarks and stable `data-testid` selectors used by later tasks.

- [ ] **Step 1: Write the failing shell test**

Create the browser harness and first test:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const chromePath = process.env.CHICKMARK_CHROME_PATH
  ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const prototypePath = path.resolve(
  process.cwd(),
  'prototypes/dashboard_v6_intelligence.html',
);

async function withPage(run, viewport = { width: 1440, height: 1000 }) {
  const browser = await chromium.launch({
    headless: true,
    executablePath: chromePath,
  });
  const page = await browser.newPage({ viewport });
  const externalRequests = [];
  page.on('request', (request) => {
    if (/^https?:/.test(request.url())) externalRequests.push(request.url());
  });
  try {
    await page.goto(pathToFileURL(prototypePath).href);
    await run({ page, externalRequests });
  } finally {
    await browser.close();
  }
}

test('renders the ChickMark intelligence shell with fixture disclosure', async () => {
  await withPage(async ({ page, externalRequests }) => {
    assert.equal(await page.title(), 'ChickMark — Intelligent Dashboard Mock');
    await page.getByRole('heading', { name: 'Operational Intelligence' }).waitFor();
    assert.equal(await page.getByTestId('fixture-badge').textContent(), 'Fixture data');
    assert.equal(await page.getByTestId('executive-pulse').count(), 1);
    assert.equal(await page.getByTestId('action-center').count(), 1);
    assert.equal(await page.getByTestId('diagnostic-workspace').count(), 1);
    assert.equal(await page.getByTestId('operational-sectors').count(), 1);
    assert.deepEqual(externalRequests, []);
  });
});
```

- [ ] **Step 2: Run the shell test and verify RED**

Run:

```bash
NODE_PATH=/Users/ibrahimradi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules \
/Users/ibrahimradi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node \
--test test/prototypes/dashboard_v6_intelligence_test.mjs
```

Expected: FAIL because `prototypes/dashboard_v6_intelligence.html` does not exist.

- [ ] **Step 3: Implement the minimal semantic shell**

Create an HTML document with these exact roots and tokens:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>ChickMark — Intelligent Dashboard Mock</title>
  <style>
    :root {
      --primary:#1769D8; --primary-light:#079FE0; --primary-dark:#193FC2;
      --accent:#E65100; --bg:#F5F8FC; --surface:#FFFFFF;
      --surface-variant:#F9FAFB; --text:#111827; --text-2:#6B7280;
      --text-3:#9CA3AF; --border:#E5E7EB; --good:#388E3C;
      --good-bg:#E8F5E9; --warn:#E67E22; --warn-bg:#FFF3E0;
      --error:#DC2626; --error-bg:#FEF2F2; --benchmark:#CBD5E1;
      --radius:10px; --pill:999px;
    }
  </style>
</head>
<body>
  <header><h1>Operational Intelligence</h1><span data-testid="fixture-badge">Fixture data</span></header>
  <main>
    <section data-testid="executive-pulse" aria-label="Executive pulse"></section>
    <section data-testid="action-center" aria-label="Intelligent action center"></section>
    <section data-testid="diagnostic-workspace" aria-label="Root-cause analysis"></section>
    <section data-testid="operational-sectors" aria-label="Operational sectors"></section>
  </main>
</body>
</html>
```

Add the branded page header, customer/hatchery/flock scope controls, a freshness label, empty executive cards, empty action and diagnostic panels, and station-shell cards.

- [ ] **Step 4: Run the shell test and verify GREEN**

Run the Task 1 test command.

Expected: PASS with one passing test and no external requests.

- [ ] **Step 5: Commit Task 1**

```bash
git add prototypes/dashboard_v6_intelligence.html test/prototypes/dashboard_v6_intelligence_test.mjs
git commit -m "feat: add intelligent dashboard prototype shell"
```

---

### Task 2: Fixture Model, Global Filters, Executive Pulse, And Insight Drill-Down

**Files:**
- Modify: `test/prototypes/dashboard_v6_intelligence_test.mjs`
- Modify: `prototypes/dashboard_v6_intelligence.html`

**Interfaces:**
- Consumes: shell selectors from Task 1.
- Produces:
  - `APP_FIXTURES.customers`
  - `APP_FIXTURES.observations`
  - `state.global = { customerId, hatcheryId, flockId, windowDays }`
  - `deriveDashboardState(state)`
  - `renderGlobalScope()`
  - `renderExecutivePulse(derived)`
  - `renderActionCenter(derived)`
  - `openInsight(insightId)`

- [ ] **Step 1: Write failing global-filter and insight tests**

Append:

```js
test('global scope reconciles executive metrics and ranked actions', async () => {
  await withPage(async ({ page }) => {
    const hatchability = page.getByTestId('kpi-hatchability-value');
    assert.equal(await hatchability.textContent(), '84.2%');
    await page.getByLabel('Flock').selectOption('flock-north');
    assert.equal(await hatchability.textContent(), '88.1%');
    assert.match(await page.getByTestId('action-rank-1').textContent(), /Shell quality/);
    assert.match(await page.getByTestId('scope-summary').textContent(), /North Star/);
  });
});

test('an intelligent action opens the linked sector comparison', async () => {
  await withPage(async ({ page }) => {
    await page.getByTestId('action-open-est-variability').click();
    const sector = page.getByTestId('sector-egg-quality');
    await sector.scrollIntoViewIfNeeded();
    assert.equal(await sector.getAttribute('data-expanded'), 'true');
    assert.equal(await page.getByTestId('egg-quality-mode-snapshot').getAttribute('aria-pressed'), 'true');
    assert.equal(await page.getByLabel('Egg Quality metric').inputValue(), 'eggCvPct');
    assert.match(await page.getByTestId('egg-quality-selection-summary').textContent(), /House 2/);
  });
});
```

- [ ] **Step 2: Run the two new tests and verify RED**

Run the Task 1 test command.

Expected: the shell test passes; the two new tests FAIL because KPI values, fixture options, actions, and sector drill-down behavior are absent.

- [ ] **Step 3: Implement fixture derivation and global rendering**

Add embedded fixtures containing at least:

```js
const APP_FIXTURES = {
  customers: [
    {
      id: 'customer-demo',
      name: 'Nile Poultry Group',
      hatcheries: [{
        id: 'hatchery-cairo',
        name: 'Cairo Central',
        flocks: [
          { id: 'flock-prime', name: 'Prime 42', breed: 'Ross 308' },
          { id: 'flock-north', name: 'North Star', breed: 'Cobb 500' },
        ],
      }],
    },
  ],
  observations: [],
};

const state = {
  global: {
    customerId: 'customer-demo',
    hatcheryId: 'hatchery-cairo',
    flockId: 'flock-prime',
    windowDays: 30,
  },
  expandedSector: null,
  comparisons: {},
};
```

Populate observations for multiple ages and stable House/Machine/Trolley/Tray identities. Give `flock-prime` hatchability `84.2` and `flock-north` hatchability `88.1`. Implement deterministic derivation:

```js
function deriveDashboardState(appState) {
  const rows = APP_FIXTURES.observations.filter(
    (row) => row.flockId === appState.global.flockId,
  );
  return {
    rows,
    hatchability: latestMetric(rows, 'hatchability'),
    actions: rankInsights(buildInsights(rows)),
    scopeLabel: resolveScopeLabel(appState.global),
  };
}
```

Render reconciled KPI cards, forecast signals, action cards with evidence/confidence text, and the root-cause summary from the same derived rows. `openInsight('est-variability')` must update only the linked sector state:

```js
function openInsight(insightId) {
  const insight = deriveDashboardState(state).actions.find((item) => item.id === insightId);
  state.expandedSector = insight.sectorId;
  state.comparisons[insight.sectorId] = {
    mode: 'snapshot',
    period: insight.period,
    layers: insight.layers,
    sampleIds: insight.sampleIds,
    metric: insight.metric,
    baseline: 'bmk',
    view: 'chart',
  };
  renderApp();
  document.querySelector(`[data-testid="sector-${insight.sectorId}"]`)
    ?.scrollIntoView({ behavior: reducedMotion() ? 'auto' : 'smooth', block: 'start' });
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the Task 1 test command.

Expected: three passing tests.

- [ ] **Step 5: Commit Task 2**

```bash
git add prototypes/dashboard_v6_intelligence.html test/prototypes/dashboard_v6_intelligence_test.mjs
git commit -m "feat: add dashboard intelligence and scope drill-down"
```

---

### Task 3: Data-Aware Sector Hierarchy And Snapshot BMK Comparison

**Files:**
- Modify: `test/prototypes/dashboard_v6_intelligence_test.mjs`
- Modify: `prototypes/dashboard_v6_intelligence.html`

**Interfaces:**
- Consumes: `state.comparisons`, fixture observations, and insight drill-down from Task 2.
- Produces:
  - `SECTOR_CONFIGS`
  - `ensureComparisonState(sectorId)`
  - `availableGroups(sectorId, comparisonState)`
  - `renderComparisonControls(sectorId)`
  - `renderSnapshotChart(sectorId)`
  - `renderVarianceTable(sectorId)`

- [ ] **Step 1: Write failing hierarchy and snapshot tests**

Append:

```js
test('sector hierarchy exposes only supported layers and paired BMK bars', async () => {
  await withPage(async ({ page }) => {
    await page.getByTestId('sector-egg-quality-toggle').click();
    const sector = page.getByTestId('sector-egg-quality');
    assert.equal(await sector.getByRole('button', { name: 'House' }).count(), 1);
    assert.equal(await sector.getByRole('button', { name: 'Machine' }).count(), 0);
    assert.equal(await sector.getByRole('button', { name: 'Tray' }).count(), 1);

    await sector.getByRole('button', { name: 'House' }).click();
    await sector.getByLabel('Egg Quality samples').selectOption(['house-1']);
    await sector.getByLabel('Egg Quality metric').selectOption('eggCvPct');

    assert.equal(await sector.locator('[data-series="actual"]').count(), 1);
    assert.equal(await sector.locator('[data-series="bmk"]').count(), 1);
    assert.match(await sector.getByTestId('egg-quality-selection-summary').textContent(), /House 1 · CV% · BMK/);
    assert.match(await sector.getByTestId('egg-quality-variance-table').textContent(), /Actual/);
  });
});

test('snapshot comparison caps visual bars and keeps ranked variance readable', async () => {
  await withPage(async ({ page }) => {
    await page.getByTestId('sector-setter-est-toggle').click();
    const sector = page.getByTestId('sector-setter-est');
    await sector.getByRole('button', { name: 'Machine' }).click();
    await sector.getByLabel('Setter EST samples').selectOption([
      'setter-01', 'setter-02', 'setter-03', 'setter-04',
      'setter-05', 'setter-06', 'setter-07',
    ]);
    assert.equal(await sector.locator('[data-series="actual"]').count(), 0);
    assert.match(await sector.getByTestId('setter-est-dense-summary').textContent(), /7 samples ranked by variance/);
  });
});
```

- [ ] **Step 2: Run the new tests and verify RED**

Run the Task 1 test command.

Expected: earlier tests pass; hierarchy/snapshot tests FAIL because sector configs, sample filtering, SVG bars, and dense summary do not exist.

- [ ] **Step 3: Implement sector configs and snapshot rendering**

Define real-core fixture sectors:

```js
const SECTOR_CONFIGS = {
  'egg-quality': {
    label: 'Egg Quality',
    station: 'Egg Storage & Handling',
    axis: 'age',
    layers: ['house', 'tray'],
    metrics: ['eggAvgWeight', 'eggUniformityPct', 'eggCvPct', 'uvAffectedPct'],
  },
  'setter-est': {
    label: 'Setter EST',
    station: 'Setters',
    axis: 'visit',
    layers: ['machine', 'trolley', 'tray'],
    metrics: ['estAvg', 'estCvPct'],
  },
  'hatch-results': {
    label: 'Hatch Results',
    station: 'Hatch Analysis & Egg Breakouts',
    axis: 'age',
    layers: ['house', 'machine'],
    metrics: ['fertility', 'hatchability', 'lateDeadPct'],
  },
  'chick-quality': {
    label: 'Chick Quality',
    station: 'Chicks',
    axis: 'age',
    layers: ['house', 'machine', 'trolley'],
    metrics: ['pasgarScore', 'navelPct', 'chickCvPct'],
  },
};
```

Render hierarchy buttons from `config.layers`, searchable multi-select samples, metric/baseline selectors, calculation/freshness labels, paired inline SVG `<rect>` elements with `data-series="actual"` and `data-series="bmk"`, and an exact variance table. If selected sample count exceeds six, replace the bar SVG with the dense ranked summary.

- [ ] **Step 4: Run tests and verify GREEN**

Run the Task 1 test command.

Expected: five passing tests.

- [ ] **Step 5: Commit Task 3**

```bash
git add prototypes/dashboard_v6_intelligence.html test/prototypes/dashboard_v6_intelligence_test.mjs
git commit -m "feat: add hierarchical sample and BMK comparisons"
```

---

### Task 4: Cumulative Age/Visit Lines, Coverage, And Dense-Selection Range

**Files:**
- Modify: `test/prototypes/dashboard_v6_intelligence_test.mjs`
- Modify: `prototypes/dashboard_v6_intelligence.html`

**Interfaces:**
- Consumes: sector configuration and selected stable sample identities from Task 3.
- Produces:
  - `buildCumulativeSeries(sectorId, comparisonState)`
  - `renderCumulativeChart(sectorId)`
  - `renderCumulativeTable(sectorId)`
  - `renderRangeFallback(sectorId)`

- [ ] **Step 1: Write failing cumulative behavior tests**

Append:

```js
test('cumulative mode plots selected stable samples across ages with BMK', async () => {
  await withPage(async ({ page }) => {
    await page.getByTestId('sector-hatch-results-toggle').click();
    const sector = page.getByTestId('sector-hatch-results');
    await sector.getByTestId('hatch-results-mode-cumulative').click();
    await sector.getByRole('button', { name: 'House' }).click();
    await sector.getByLabel('Hatch Results samples').selectOption(['house-1', 'house-2']);
    await sector.getByLabel('Hatch Results metric').selectOption('hatchability');

    assert.equal(await sector.locator('polyline[data-series="sample"]').count(), 2);
    assert.equal(await sector.locator('polyline[data-series="bmk"][stroke-dasharray]').count(), 1);
    assert.match(await sector.getByTestId('hatch-results-coverage').textContent(), /coverage/);
    assert.match(await sector.getByTestId('hatch-results-cumulative-table').textContent(), /Age 38/);
  });
});

test('five cumulative samples switch to pool and range instead of five lines', async () => {
  await withPage(async ({ page }) => {
    await page.getByTestId('sector-setter-est-toggle').click();
    const sector = page.getByTestId('sector-setter-est');
    await sector.getByTestId('setter-est-mode-cumulative').click();
    await sector.getByRole('button', { name: 'Machine' }).click();
    await sector.getByLabel('Setter EST samples').selectOption([
      'setter-01', 'setter-02', 'setter-03', 'setter-04', 'setter-05',
    ]);

    assert.equal(await sector.locator('polyline[data-series="sample"]').count(), 0);
    assert.equal(await sector.locator('polyline[data-series="pool"]').count(), 1);
    assert.equal(await sector.locator('polygon[data-series="range"]').count(), 1);
    assert.match(await sector.getByTestId('setter-est-outliers').textContent(), /Largest variance/);
  });
});
```

- [ ] **Step 2: Run new tests and verify RED**

Run the Task 1 test command.

Expected: earlier tests pass; cumulative tests FAIL because mode switching and cumulative SVG/table renderers are absent.

- [ ] **Step 3: Implement cumulative derivation and SVG rendering**

Group fixture rows by stable sample id and ordered age/visit:

```js
function buildCumulativeSeries(sectorId, comparison) {
  const config = SECTOR_CONFIGS[sectorId];
  const rows = rowsForSector(sectorId).filter(
    (row) => comparison.sampleIds.includes(row.sampleId)
      && row.metric === comparison.metric,
  );
  return {
    axis: config.axis,
    periods: orderedPeriods(rows, config.axis),
    samples: groupStableSamples(rows),
    bmk: bmkSeries(rows),
    coverage: coverageSummary(rows, comparison.sampleIds),
  };
}
```

Render up to four sample `<polyline data-series="sample">` paths and one dashed BMK line. Represent missing periods by starting a new polyline segment instead of interpolating across the gap. For five or more samples, calculate period Pool/min/max values, draw one `<polygon data-series="range">`, one `<polyline data-series="pool">`, the dashed BMK, and a ranked outlier list. Render the exact cumulative table from the same series object.

- [ ] **Step 4: Run tests and verify GREEN**

Run the Task 1 test command.

Expected: seven passing tests.

- [ ] **Step 5: Commit Task 4**

```bash
git add prototypes/dashboard_v6_intelligence.html test/prototypes/dashboard_v6_intelligence_test.mjs
git commit -m "feat: add cumulative sample intelligence views"
```

---

### Task 5: Responsive Layout, Accessible Controls, Offline Safety, And Data States

**Files:**
- Modify: `test/prototypes/dashboard_v6_intelligence_test.mjs`
- Modify: `prototypes/dashboard_v6_intelligence.html`

**Interfaces:**
- Consumes: all Task 1–4 components.
- Produces:
  - mobile-safe layout
  - keyboard-visible focus
  - reduced-motion handling
  - no-data, one-sample, missing-BMK, partial-coverage, and invalid-child-reset states

- [ ] **Step 1: Write failing quality-gate tests**

Append:

```js
test('phone layout has no page-level horizontal overflow', async () => {
  await withPage(async ({ page }) => {
    const geometry = await page.evaluate(() => ({
      viewport: document.documentElement.clientWidth,
      scroll: document.documentElement.scrollWidth,
    }));
    assert.ok(geometry.scroll <= geometry.viewport);
    await page.getByTestId('sector-hatch-results-toggle').click();
    const after = await page.evaluate(() => ({
      viewport: document.documentElement.clientWidth,
      scroll: document.documentElement.scrollWidth,
    }));
    assert.ok(after.scroll <= after.viewport);
  }, { width: 390, height: 844 });
});

test('controls remain keyboard reachable and disclose calculation states', async () => {
  await withPage(async ({ page }) => {
    await page.keyboard.press('Tab');
    assert.notEqual(await page.evaluate(() => document.activeElement?.tagName), 'BODY');
    await page.getByTestId('sector-egg-quality-toggle').click();
    const sector = page.getByTestId('sector-egg-quality');
    assert.match(await sector.getByTestId('egg-quality-calculation').textContent(), /Sample-weighted average/);
    assert.match(await sector.getByTestId('egg-quality-coverage').textContent(), /coverage/);
  });
});

test('prototype stays self-contained after interaction', async () => {
  await withPage(async ({ page, externalRequests }) => {
    await page.getByTestId('action-open-est-variability').click();
    await page.getByTestId('egg-quality-mode-cumulative').click();
    assert.deepEqual(externalRequests, []);
    assert.equal(await page.locator('script[src],link[rel="stylesheet"],img[src^="http"]').count(), 0);
  });
});
```

- [ ] **Step 2: Run quality tests and verify RED**

Run the Task 1 test command.

Expected: at least the overflow, calculation-state, or focus assertion FAILS before responsive/accessibility polish.

- [ ] **Step 3: Implement the quality and state layer**

Add:

```css
* { box-sizing:border-box; }
html, body { max-width:100%; overflow-x:hidden; }
:focus-visible { outline:3px solid rgba(23,105,216,.35); outline-offset:2px; }
.chart-scroll { max-width:100%; overflow-x:auto; overscroll-behavior-inline:contain; }
@media (max-width: 760px) {
  .dashboard-grid, .diagnostic-grid { grid-template-columns:1fr; }
  .filter-row { overflow-x:auto; flex-wrap:nowrap; }
  .kpi-strip { grid-template-columns:repeat(2,minmax(0,1fr)); }
}
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { scroll-behavior:auto!important; transition:none!important; animation:none!important; }
}
```

Use semantic `<button>`, `<select>`, `<table>`, `<details>`, headings, `aria-pressed`, live status summaries, and visible labels. Add deterministic state messages:

```js
function comparisonAvailability(series) {
  if (!series.rows.length) return { kind: 'empty', message: 'No recorded samples in this scope.' };
  if (!series.hasBmk) return { kind: 'missing-bmk', message: 'BMK unavailable; showing actual trend only.' };
  if (series.sampleIds.length === 1) return { kind: 'single', message: 'One sample: BMK comparison available; multi-sample comparison disabled.' };
  if (series.coverage < 1) return { kind: 'partial', message: `${Math.round(series.coverage * 100)}% coverage; gaps are preserved.` };
  return { kind: 'ready', message: 'Complete comparison coverage.' };
}
```

When a global or parent hierarchy filter invalidates a child selection, keep valid ids, drop only invalid ids, and announce the reset in an `aria-live="polite"` region.

- [ ] **Step 4: Run tests and verify GREEN**

Run the Task 1 test command.

Expected: ten passing tests, zero failures, and no external requests.

- [ ] **Step 5: Commit Task 5**

```bash
git add prototypes/dashboard_v6_intelligence.html test/prototypes/dashboard_v6_intelligence_test.mjs
git commit -m "test: harden dashboard prototype behavior"
```

---

### Task 6: Final Requirement Reconciliation And Handoff Verification

**Files:**
- Modify only if verification exposes a defect:
  - `test/prototypes/dashboard_v6_intelligence_test.mjs`
  - `prototypes/dashboard_v6_intelligence.html`

**Interfaces:**
- Consumes: completed prototype and acceptance suite.
- Produces: fresh proof that the HTML opens, behaves correctly, remains offline, and satisfies the approved design.

- [ ] **Step 1: Run the complete browser acceptance suite**

Run:

```bash
NODE_PATH=/Users/ibrahimradi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules \
/Users/ibrahimradi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node \
--test test/prototypes/dashboard_v6_intelligence_test.mjs
```

Expected: ten tests pass, zero fail.

- [ ] **Step 2: Run source-level safety checks**

Run:

```bash
rg -n 'https?://|<script[^>]+src=|<link[^>]+stylesheet|<img[^>]+src=' \
prototypes/dashboard_v6_intelligence.html
```

Expected: no output.

Run:

```bash
rg -n 'Fixture data|Likely contributors|Confidence|BMK|Sample-weighted average|coverage' \
prototypes/dashboard_v6_intelligence.html
```

Expected: every required disclosure category has at least one match.

- [ ] **Step 3: Inspect the task diff**

Run:

```bash
git diff --check
git status --short
git diff --stat HEAD~5..HEAD -- \
  prototypes/dashboard_v6_intelligence.html \
  test/prototypes/dashboard_v6_intelligence_test.mjs \
  docs/superpowers/plans/2026-07-23-intelligent-dashboard-html-mock.md
```

Expected: no whitespace errors; only the intended prototype, test, and plan are attributable to this implementation.

- [ ] **Step 4: Commit any verification-only fixes**

If Step 1–3 required changes:

```bash
git add prototypes/dashboard_v6_intelligence.html test/prototypes/dashboard_v6_intelligence_test.mjs
git commit -m "fix: finalize intelligent dashboard prototype"
```

If no changes were required, do not create an empty commit.

- [ ] **Step 5: Prepare the handoff**

Report:

- Task id: `intelligent-dashboard-html-mock`
- Summary: branded intelligent HTML dashboard mock with layered insights and per-sector hierarchical comparisons
- Files changed
- Exact browser-test and safety-check commands
- Fixture-data, hypothesis, and non-production caveats
- Local clickable path to `prototypes/dashboard_v6_intelligence.html`
