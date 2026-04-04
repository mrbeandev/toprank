# Changelog

All notable changes to Toprank will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.8.0] — 2026-03-31

### Added
- **`/setup-cms` skill** — interactive wizard to connect WordPress, Strapi, Contentful, or Ghost. Detects existing config, collects credentials, tests the connection, and writes to `.env.local`.
- **WordPress CMS integration** (Phase 3.6) — `preflight_wordpress.py` + `fetch_wordpress_content.py`. REST API with Application Password auth. Extracts SEO fields from Yoast SEO (`yoast_head_json`) or RankMath (`meta.rank_math_title`).
- **Contentful CMS integration** (Phase 3.6) — `preflight_contentful.py` + `fetch_contentful_content.py`. Delivery API with Bearer token auth. Resolves linked SEO component entries (`include=1`), supports pagination up to 1000 entries/page.
- **Ghost CMS integration** (Phase 3.6) — `preflight_ghost.py` + `fetch_ghost_content.py`. Content API with auto-detection between v4+ (`/ghost/api/content/`) and v3 (`/ghost/api/v3/content/`). Uses native `meta_title`/`meta_description` fields.
- **`cms_detect.py`** — lightweight CMS routing script. Checks env vars in priority order (WP_URL → Contentful → Ghost → Strapi), exits 0 with CMS name if found, exits 2 if none configured.
- **56 unit tests** (`test/unit/test_cms_scripts.py`) covering SEO field extraction, entry normalisation, SEO audit aggregation, SSRF protection, and WordPress auth header encoding across all 4 CMSes.

### Changed
- **`seo-analysis` Phase 3.6** — rewritten from Strapi-specific to CMS-agnostic. Now routes through `cms_detect.py` and runs the appropriate preflight + fetch script via `case` statement. All CMSes produce the same normalized JSON format.
- Report template: "Strapi SEO Field Audit" → "CMS SEO Field Audit" (supports WordPress, Strapi, Contentful, Ghost).

### Fixed
- **Ghost/WordPress/Contentful false negatives** — SEO extraction no longer falls back to the content title when no explicit meta title is set. Entries with no SEO plugin / no meta title override are now correctly flagged as `missing_meta_title=True`.
- **Ghost `detect_api_path` sys.exit trap** — replaced `ghost_get()` probe (which calls `sys.exit(1)` on errors) with inline `urllib` probe, allowing the v3 API path fallback to actually run.
- **Ghost `PAGE_SIZE`** — changed from 15 (display default) to 100 (actual API max).

---

## [0.7.1] — 2026-04-01

### Fixed
- **`seo-analysis` — GSC display crash** — added `show_gsc.py` display utility to replace fragile inline Python scripts. Fixes `TypeError: string indices must be integers, not 'str'` that occurred when iterating `comparison` dict fields (which mixes string metadata and list data at the same level). Also fixes CTR being displayed as 474% instead of 4.74% (was being multiplied by 100 twice).

---

## [0.7.0] — 2026-04-01

### Added
- **`seo-analysis` — URL-first flow** — Step 0 now asks for the target website URL before running any preflight or API calls. The URL is stored and used throughout the entire audit for URL Inspection, technical crawl, and metadata fetching.
- **`seo-analysis` — URL Inspection API** (Phase 3.5) — new `url_inspection.py` script calls `POST https://searchconsole.googleapis.com/v1/urlInspection/index:inspect` for the top pages. Returns per-page indexing status (`INDEXED`, `NOT_INDEXED`, `DUPLICATE_WITHOUT_CANONICAL`, etc.), mobile usability verdict, rich result status, last crawl time, and referring sitemaps. Results surface immediately as critical flags in the report.
- **`seo-analysis` — Keyword Gap Analysis** (Phase 4.5) — finds keyword orphans (queries ranking 4-20 with no dedicated page), builds topic clusters from GSC data with pillar page recommendations, and identifies business-relevant keywords the site should rank for but has no impressions for.
- **`seo-analysis` — Deep Metadata Audit** — for each audited page, fetches the live `<title>` and `<meta description>`, cross-references against top GSC queries for title/query alignment, checks character counts, detects duplicate titles, and audits Open Graph tags. Outputs a structured per-page table.
- **`seo-analysis` — Deep Schema Markup Audit** — detects site type (E-commerce, SaaS, Local Business, etc.), defines expected schema types per site type, audits each page's `<script type="application/ld+json">` blocks, and flags missing high-impact schema and errors in existing schema. Cross-references with URL Inspection rich result findings.
- **`seo-analysis` — Skill Handoffs** (Phase 7) — after delivering the report, surfaces targeted follow-up actions: `/meta-tags-optimizer` for pages with metadata issues, `/schema-markup-generator` for schema gaps, `/keyword-research` with seed terms from the gap analysis.
- **Branded vs non-branded segmentation** (`branded_split`) — pass `--brand-terms "Acme,AcmeCorp"` to split all GSC traffic into branded and non-branded segments. Each segment gets its own clicks, impressions, CTR, average position, query count, and top-20 queries. Non-branded metrics become the true baseline for Quick Wins and content recommendations. Returns `null` if no brand terms provided.
- **Page group clustering** (`page_groups`) — automatically buckets top pages by URL path pattern (/blog/, /products/, /locations/, /services/, /pricing/, /docs/, /about/, /faq/, /lp/, /case-studies/) with per-section aggregate stats. Exposes template-level problems: "all /products/ pages have 0.8% CTR" can be fixed once, not 50 times.
- **Winner/loser scoring for cannibalization** — each `cannibalization` entry now includes `winner_page`, `winner_reason`, `loser_pages`, and `recommended_action` ("consolidate: 301 redirect..." or "monitor: possible SERP domination").
- **`test/unit/test_url_inspection.py`** — 25 unit tests covering `normalize_site_url_for_inspection`, `parse_inspection_result`, and `summarize_findings`.
- **35 new unit tests** covering `classify_branded`, `derive_branded_split`, `cluster_page_groups`, and all new cannibalization fields.
- **Strapi CMS integration** (Phase 3.6) — the `/seo-analysis` skill now cross-references your published Strapi content against GSC data. Three new scripts:
  - **`preflight_strapi.py`** — validates config, tests connectivity, detects Strapi v4 vs v5. Exit code 2 = not configured (non-fatal skip).
  - **`fetch_strapi_content.py`** — paginates all published entries, extracts SEO fields from the official `strapi-community/plugin-seo` component and root-level fallbacks, writes a structured JSON audit.
  - **`push_strapi_seo.py`** — batch write-back with before/after diff preview, stale-write guard, and locale support for v5 localized content.
- **59 new unit tests** for the Strapi scripts — version detection, entry normalisation, SEO audit counting, payload building, stale-write guard logic, and SSRF IP classification.

### Changed
- **`seo-analysis` — `analyze_gsc.py` parallelized** — all 9 GSC API calls now run concurrently via `ThreadPoolExecutor`, cutting wall-clock data collection time by ~70%. Each worker has an exception guard so a single failed call logs an error and continues rather than crashing the script.
- **`url_inspection.py` — parallel URL inspection** — inspections run with `--concurrency 3` (default). `--max-urls` default reduced from 20 to 5 to stay well within the 2000/day API quota. Worker failures are caught and logged without aborting the run.
- **`seo-analysis` — technical crawl capped at 5 pages** — Phase 5 now has a hard cap of 5 pages (homepage first, then top by clicks, then flagged pages) to keep the audit fast without losing insight.
- **`seo-analysis` — broader OAuth scope** — re-auth instructions throughout the skill now include both `webmasters` and `webmasters.readonly` scopes, required for the URL Inspection API.
- **`seo-analysis`** Phase 2 now asks for brand terms before pulling data.
- **`seo-analysis`** Phase 4 adds "Branded vs Non-Branded Split" and "Page Group Performance" sections.
- **`seo-analysis/evals/evals.json`** — 3-scenario test suite covering URL-first behavior, no-GSC technical fallback, and comprehensive GSC+inspection audit.
- Cannibalization `competing_pages` now sorted by position ascending (best first) instead of clicks descending.
- Strapi integration is **opt-in and non-blocking** — if `STRAPI_URL` is not configured, Phase 3.6 skips silently.

---

## [0.6.1] — 2026-03-31

### Added
- **`test/install.test.sh`** — mock-HOME install test suite for `./setup`. 61 assertions across 6 scenarios: Claude Code global install (symlinks, targets, preamble injection), auto-detect via path, idempotency, real-directory protection, Codex install (openai.yaml + SKILL.md symlinks), and invalid `--host` flag handling. Includes a count-guard that fails fast if a new skill is added to the repo without updating the test's SKILLS array.

### Changed
- **`seo-analysis`** — deeper Google Search Console data in every audit. The script now pulls four additional data sets from a single API session:
  - **Cannibalization** (`cannibalization`) — queries where multiple pages compete, with per-page click/impression breakdown. Previously the skill inferred this from single-dimension data; now it uses the real `[query, page]` dimension so every recommendation names specific URLs.
  - **CTR gaps by page** (`ctr_gaps_by_page`) — high-impression, low-CTR pairs at the query+page level. Replaces query-only CTR opportunities so every title/meta rewrite suggestion includes the exact page to fix.
  - **Country split** (`country_split`) — top 20 countries by clicks with CTR and position. Surfaces geo opportunities and region-specific ranking problems.
  - **Search type breakdown** (`search_type_split`) — web, image, video, news, Discover, and Google News traffic shown separately. Many sites have Discover or image traffic they don't know about.
- `device_split` now includes CTR and position alongside clicks and impressions.
- Phase 4 analysis guidance updated to use the new data fields directly.
- New "Segment Analysis" subsection added to Phase 4 for device, country, and search type interpretation.
- Unit tests: 49 → 79 (+30 tests covering all new functions with boundary and edge case coverage).

---

## [0.6.0] — 2026-03-30

### Added
- **`keyword-research`** — new skill for keyword discovery, intent classification, difficulty assessment, opportunity scoring, and topic clustering. Includes reference materials for intent taxonomy, prioritization framework, cluster templates, and example reports.
- **`meta-tags-optimizer`** — new skill for creating and optimizing title tags, meta descriptions, Open Graph, and Twitter Card tags with A/B test variations and CTR analysis. Includes reference materials for tag formulas, CTR benchmarks, and code templates.
- **`schema-markup-generator`** — new skill for generating JSON-LD structured data (FAQ, HowTo, Article, Product, LocalBusiness, etc.) with validation guidance and rich result eligibility checks. Includes reference materials for schema templates, decision tree, and validation guide.
- **`geo-content-optimizer`** — new skill for optimizing content to appear in AI-generated responses (ChatGPT, Perplexity, Google AI Overviews, Claude). Scores GEO readiness and applies citation, authority, and structure optimization techniques. Includes reference materials for AI citation patterns, GEO techniques, and quotable content examples.

### Changed
- **README.md** — updated with documentation for all 4 new skills, expanded install instructions and directory tree

---

## [0.5.1] — 2026-03-27

### Security
- **Predictable /tmp paths** — `analyze_gsc.py` and `list_gsc_sites.py` now use `gsc_analysis_{uid}.json` / `gsc_sites_{uid}.json` via `tempfile.gettempdir()` + `os.getuid()`, preventing cross-user data exposure on multi-user systems
- **`.gstack/` gitignored** — local security audit reports excluded from git history
- **Test dependency lockfile** — added `requirements-test.lock` (pip-compiled) to pin test dependencies and prevent supply-chain drift

---

## [0.5.0] — 2026-03-27

### Added
- **`preflight.py`** — pre-flight check that runs before any GSC operations; detects gcloud with OS-specific install instructions (Homebrew / apt / dnf / curl / winget), auto-triggers `gcloud auth` browser flow if no ADC credentials found
- **`setup.py`** — cross-platform Python equivalent of `./setup` for Windows users who can't run bash; falls back to directory junctions (no admin rights required) when symlinks are unavailable
- **Phase 0 in SKILL.md** — preflight step added before GSC access check; also restores the "skip GSC → Phase 5" escape hatch for technical-only audits

### Changed
- **`seo-analysis/SKILL.md`** — Phase 1 simplified (error cases now handled by preflight); Phase 1 bash block is self-contained (no shell variable leak from Phase 0)

---

## [0.4.2] — 2026-03-27

### Added
- **README demo section** — "See It Work" example conversation showing end-to-end `/seo-analysis` flow for clearer onboarding

### Changed
- **Auto-upgrade on every skill use** — removed the 4-option prompt (Yes / Always / Not now / Never); updates now apply automatically whenever `UPGRADE_AVAILABLE` is detected
- **Update check frequency** — reduced UP_TO_DATE cache TTL from 60 min to 5 min so checks run on nearly every skill invocation
- **Zero-dependency GSC auth** — removed `google-auth` Python package requirement; reverts 0.4.1 approach; scripts now call `gcloud auth application-default print-access-token` directly via subprocess and use stdlib `urllib` for HTTP, eliminating the `pip install` setup step
- **`gsc_auth.py` removed** — auth logic inlined in `list_gsc_sites.py` and `analyze_gsc.py`; simpler, no shared module
- **SKILL.md Phase 1** — GSC setup instructions updated to reflect the simpler auth flow

### Security
- **Predictable /tmp paths** — GSC output files now use `gsc_analysis_{uid}.json` and `gsc_sites_{uid}.json` instead of shared paths, preventing cross-user data exposure on multi-user systems
- **`.gstack/` gitignored** — security audit reports are now excluded from git commits
- **Test dependency lockfile** — added `requirements-test.lock` (pip-compiled) to pin exact versions and prevent supply-chain drift

---

## [0.4.1] — 2026-03-27

### Fixed
- **GSC quota project header** — replaced raw `urllib` HTTP calls with `google-auth` library (`AuthorizedSession`), which automatically sends the `x-goog-user-project` header required for ADC user credentials; this was the root cause of 403 errors during onboarding
- **Auto-detect quota project** — scripts now read `quota_project_id` from ADC credentials and fall back to `gcloud config get-value project` if missing, eliminating the manual `set-quota-project` step

### Changed
- **Shared auth module** — extracted `gsc_auth.py` with `get_credentials()`, `get_session()`, and `_ensure_quota_project()` to eliminate duplicated auth logic between `list_gsc_sites.py` and `analyze_gsc.py`
- **SKILL.md Phase 1** — streamlined GSC setup instructions from ~50 lines to ~25 lines for faster onboarding and lower token usage
- **gsc_setup.md** — updated setup guide to reflect 2-step process (`pip install google-auth` + `gcloud auth application-default login`) and documented new troubleshooting entries

### Added
- **`google-auth` dependency** — new pip requirement for proper Google API authentication
- **4 new unit tests** for `_ensure_quota_project()` covering: already-set, auto-detect from gcloud, gcloud not found, gcloud returns empty

---

## [0.4.0] — 2026-03-27

### Added
- **`content-writer` skill** — standalone SEO content creation, directly invocable without running a full SEO audit
  - Handles three jobs: new blog posts, new landing pages, and improving existing pages
  - 6-step workflow: determine job → gather context → read guidelines → research & plan → write → quality gate
  - Follows Google's E-E-A-T and Helpful Content guidelines via shared reference doc
  - Outputs publication-ready content with SEO metadata, JSON-LD structured data, internal linking plan, and publishing checklist
  - Smart content type detection from user intent (informational → blog, transactional → landing page)
- **`content-writing.md` reference doc** — single source of truth for Google content best practices (E-E-A-T framework, helpful content signals, blog/landing page templates, search intent matching, on-page SEO checklist, anti-patterns including AI content pitfalls)
- **`seo-analysis` Phase 7** — optional content generation after audit; spawns up to 5 content agents in parallel when content gaps are identified, each reading the shared `content-writing.md` guidelines

### Changed
- **CONTRIBUTING.md** — expanded with detailed SKILL.md structure, script requirements, reference file guidelines, and skill ideas table
- **README.md** — added `content-writer` to skills table and updated project description

---

## [0.3.0] — 2026-03-27

### Added
- **Python test suite** — full pytest infrastructure under `test/` replacing the prior TypeScript/Bun approach; no build step required
  - `test/unit/` — 42 fast unit tests (stdlib only, no API calls); covers date math, GSC data processing, report structure, and skill SKILL.md content validation
  - `test/test_skill_e2e.py` — E2E skill tests gated behind `EVALS=1`; uses mock `gcloud` + mock `analyze_gsc.py` fixture to run the full skill workflow without real credentials
  - `test/test_skill_llm_eval.py` — LLM-as-judge quality evals gated behind `EVALS=1`; scores report clarity, actionability, and phase coverage on a 1–5 scale
  - `test/test_skill_routing_e2e.py` — routing evals verify the skill triggers on SEO prompts and stays silent on unrelated requests
  - `test/helpers/` — session runner (spawns `claude -p --output-format stream-json`), LLM judge, eval store, and diff-based test selection
  - `test/fixtures/` — mock gcloud binary, mock analyze_gsc.py, and sample GSC JSON fixture data
  - `conftest.py` — root-level pytest config for import path setup
  - `requirements-test.txt` — minimal test dependencies

### Fixed
- **Routing tests** — added harness failure guard; `should-not-trigger` tests no longer silently pass when the subprocess times out or crashes
- **Env isolation** — test subprocess now strips `ANTHROPIC_*` vars (in addition to `CLAUDE_*`) to prevent `ANTHROPIC_BASE_URL` or `ANTHROPIC_MODEL` from redirecting evals to an unintended endpoint
- **LLM judge retry** — exponential backoff (3 attempts: 1s, 2s, 4s) replaces single-retry on rate limit
- **Mock gcloud** — removed fall-through to real `gcloud` binary that caused infinite recursion when mock was first in PATH
- **`.gitignore`** — restored credential patterns (`credentials.json`, `token.json`, `.env`, etc.) accidentally dropped in initial commit

---

## [0.2.3] — 2026-03-27

### Changed
- Simplified CONTRIBUTING.md — removed skill ideas table and verbose guidelines, kept essentials for getting started

---

## [0.2.2] — 2026-03-27

### Changed
- Rewrote README intro for clarity and power — headline now communicates that Toprank analyzes, recommends, and fixes SEO issues directly in your repo

---

## [0.2.0] — 2026-03-27

### Added
- **Autoupdate system** — skills now check GitHub for new versions on every invocation
  - `bin/toprank-update-check` — fetches `VERSION` from GitHub with 60-min cache; outputs `UPGRADE_AVAILABLE <old> <new>` or nothing
  - `bin/toprank-config` — read/write `~/.toprank/config.yaml`; supports `update_check`, `auto_upgrade` keys
  - `toprank-upgrade/SKILL.md` — upgrade skill with inline and standalone flows, snooze (24h/48h/7d backoff), auto-upgrade mode, changelog diff
  - Preamble in `seo-analysis` and auto-inject via `setup` for all future skills
  - `bin/preamble.md` — single source of truth for the preamble template
- `VERSION` file — tracks current release for update checks

### Fixed
- `toprank-update-check`: validate local VERSION format before writing cache; exit after `JUST_UPGRADED` to prevent dual stdout output; move `mkdir -p` to top of script
- `setup`: atomic SKILL.md writes via temp file + `os.replace()`; add `pipefail` to catch silent Python errors
- `toprank-upgrade`: clear stale `.bak` before vendored upgrade to prevent collision

---

## [0.2.1] — 2026-03-27

### Changed
- **`seo-analysis` Phase 1** — replaced two-step auth check (token print + separate site list) with single `list_gsc_sites.py` call that tests auth, scopes, and GSC access in one shot; added distinct handling for each failure mode (wrong account, wrong scopes, API not enabled, gcloud not installed)
- **`seo-analysis` script paths** — replaced hardcoded `~/.claude/skills/seo-analysis/scripts/` with a `find`-based `SKILL_SCRIPTS` lookup that works for Claude Code, Codex, and custom install paths; added guard for empty result so missing installs fail with a clear error instead of a confusing path error
- **`seo-analysis` property selection** — added explicit rule to prefer domain property (`sc-domain:example.com`) over URL-prefix when both exist for the same site
- **`gsc_setup.md`** — moved "Which Google Account" guidance to top (most common failure cause); replaced broken `oauth_setup.py` Option B with Linux (Debian/Ubuntu, RPM) and Windows install instructions; fixed deprecated `apt-key` with `gpg --dearmor` for Debian 12+/Ubuntu 24.04+; expanded troubleshooting to cover `insufficient_scope` 403s

### Fixed
- **`list_gsc_sites.py`** — unhandled `FileNotFoundError` when gcloud is not installed now shows a clean error message; added `URLError` handling for network failures (DNS, TLS, proxy)
- **`analyze_gsc.py`** — same `FileNotFoundError` and `URLError` fixes
- **`gsc_setup.md`** — removed reference to `oauth_setup.py` which did not exist
- **`seo-analysis` SKILL.md** — corrected error-branch description from "Python traceback" to "ERROR: gcloud not found" to match the actual script output

---

## [0.1.1] — 2026-03-27

### Changed
- **README intro** — rewritten to lead with user outcome ("Finally know what to do about your SEO") and emphasize zero-risk install; blockquote examples now show real questions users would type

---

## [0.1.0] — 2026-03-26

### Added
- **`seo-analysis` skill** — comprehensive SEO audit powered by Google Search Console
  - Phase 1: GSC API setup detection and guided auth via `gcloud` Application Default Credentials
  - Phase 2: Auto-detect site URL from website repo (`package.json`, `next.config.js`, `astro.config.*`, etc.) or prompt for URL
  - Phase 3: Data collection — top queries, top pages, position buckets (1–3, 4–10, 11–20, 21+), CTR opportunities, 28-day period comparison, device split
  - Phase 4a: Search Console analysis — quick wins, content gaps, traffic drops
  - Phase 4b: Technical SEO audit — indexability, meta tags, heading structure, structured data, performance signals
  - Phase 5: Structured report with executive summary, traffic snapshot, and 30-day action plan
- `scripts/list_gsc_sites.py` — list all GSC properties for the authenticated account
- `scripts/analyze_gsc.py` — pull and process GSC data, output structured JSON
- `references/gsc_setup.md` — complete setup guide for gcloud ADC and OAuth fallback
