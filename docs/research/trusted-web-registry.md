# Research: Trusted web — whitelist, registry, freshness, caching (FIN-66)

**Ticket:** FIN-66 · **Repo:** Adisu Serategna planning · **Date:** 2026-08-18

**Status:** Decision recorded via grilling (FIN-66, wayfinder:grilling on map FIN-57). All URLs below were live-verified on 2026-08-18 (HTTP fetch + DNS + Wayback where needed). SPAs verified as client-rendered (shell HTML only) by raw-HTTP fetch.

---

## Summary of decisions

1. **Whitelist = verified official domains, topic-area curated.** 4 of the 6 legacy whitelisted domains were dead, private, or wrong (see table below); `ethiopianbusiness.org` and `ethiopianinvestment.org` were private/parked sites, `molsa.gov.et` is an outdated ministry (now Ministry of Labour and Skills, `mols.gov.et`), `ethiocontrol.gov.et` never existed (now Institute of Ethiopian Standards, `ies.gov.et`), `erca.gov.et` was dissolved in 2018 (Ministry of Revenues, `mor.gov.et`), `mint.gov.et` is unreachable since ~2020.
2. **Config-driven.** Whitelist + registry move from the hardcoded `TRUSTED_DOMAINS` constant in `ai-service/infrastructure/tools/local/search_trusted_web.py` into `Settings`/env with the verified set as default.
3. **Curated deep-link registry per topic** (ADR-002's intended "direct URL mapping per topic area", never realized): the LLM picks only URLs from the registry (**strict registry-only**); anything else is refused with the list of available topics.
4. **Registry keyed by compliance types + topic clusters** (`business_registration`, `trade_license`, `tax_registration` + permits/labor/standards/investment/IP/SME/e-services). Guide-step `external_links` may *feed* the registry later (see Fog).
5. **Client-rendered SPAs are excluded from curated entries** (`etrade.gov.et`, `business.gov.et`, `mor.gov.et` deep links return shell HTML to a raw fetch) but their domains stay whitelisted, uncurated. The tool emits an honest "no extractable content" signal when extraction yields nothing. Scoped JS rendering is a follow-up ticket (FIN-81); `mor.gov.et` tax pages are the high-value candidate.
6. **Caching:** in-process TTL cache (1h) keyed by canonical URL; the last-good snapshot (raw + extracted + fetched_at) is retained to serve as the outage fallback.
7. **Freshness:** best-effort conditional requests (`If-Modified-Since`/`ETag` where the site supports it); every tool result carries `Source: <label>` and `As of: <RFC3339 UTC>` lines so answers can state "as of <date>".
8. **Failure ladder** (after the one transient retry already decided in FIN-65): stale snapshot served with an explicit "cached as of" warning → per-topic fallback URL (fresh fetch) → graceful "couldn't reach <site>" result, answer from KB alone.
9. **Security (audit findings ride along):** `http://` rejected except an explicit per-domain exception list; redirect targets re-vetted (same-origin or whitelisted); bounded response-body read (cap before extraction).
10. **Amharic:** where a verified Amharic page exists it is registered per-locale so the LLM can pick the `am` URL for Amharic conversations.

Follow-ups created: **CRAG-style KB-first web gate** (FIN-79), **Structured citations for web results** (FIN-80), **Scoped JS rendering for SPA ministry pages** (FIN-81).

---

## Verified whitelist (domains)

| Domain | Agency | Status | TLS | Notes |
|---|---|---|---|---|
| `motri.gov.et` | Ministry of Trade & Regional Integration | ✅ live, server-rendered | strict | EN `/en`, AM `/am` default |
| `mor.gov.et` | Ministry of Revenues | ✅ live (SPA routes) | **exception** | CSR shell on `/tax-types`, `/tax-calendar`; TLS chain incomplete |
| `mols.gov.et` | Ministry of Labour and Skills | ✅ live, server-rendered | strict | WordPress; slow/flaky from abroad — use long timeouts |
| `ies.gov.et` | Institute of Ethiopian Standards | ✅ live, server-rendered | strict | mirror `ethiostandards.org` |
| `investethiopia.gov.et` | Ethiopian Investment Commission | ✅ live, server-rendered | strict | incentives in proclamations/directives + PDFs |
| `investinethiopia.gov.et` | EIC eInvest portal | ⚠ reachable | strict | SPA — uncurated |
| `eipa.gov.et` | Intellectual Property Authority | ✅ live, server-rendered | strict | EN/AM mixed on same pages |
| `manuf-sme.gov.et` | Ethiopian Enterprise Development | ✅ live, server-rendered | strict | AM `/am/<slug>` |
| `moi.gov.et` | Ministry of Industry | ✅ live, server-rendered | strict | |
| `eservices.gov.et` | eService portal (MInT) | ✅ live, SSR, bilingual | **exception** | SAN mismatch; `/am` default |
| `etrade.gov.et` | e-Trade / OTRS (MoTRI) | ⚠ reachable | **exception** | Angular SPA, login-gated |
| `business.gov.et` | Business Portal | ⚠ reachable | **exception** | SPA; content unverifiable |

Dropped from the legacy whitelist: `mint.gov.et` (unreachable), `erca.gov.et` (dissolved), `molsa.gov.et` (renamed), `ethiocontrol.gov.et` (never existed), `ethiopianbusiness.org` (private/parked), `ethiopianinvestment.org` (private). `gdop.gov.et` excluded (internal gov-ops platform, not citizen-facing).

**TLS exception list** (`allow_insecure_http`, exactly four domains): `etrade.gov.et`, `business.gov.et`, `mor.gov.et`, `eservices.gov.et` — incomplete chains / SAN mismatches; plain `http://` works. Everything else is strict; redirect targets are always re-vetted regardless.

---

## Curated registry (per topic)

Verified 2026-08-18. `render` = server (content extractable via raw HTML) | spa (shell only). `tls` = strict | relaxed.

| Topic | Agency | URL | Title | AM | render | tls | Fallback URL |
|---|---|---|---|---|---|---|---|
| business registration | MoTRI | `https://motri.gov.et/en/sector/--2` | Trade System and Licensing | `/am/sector/--2` | server | strict | `https://eservices.gov.et/am` |
| trade license | MoTRI | `https://motri.gov.et/en/sector/--2` | Trade System and Licensing | `/am/sector/--2` | server | strict | `https://eservices.gov.et/am` |
| tax registration & taxes | *(none curated — `mor.gov.et` routes are CSR)* | — | — | — | spa | relaxed | `https://eservices.gov.et/am` (portal; KB `tax_code` docs carry substance; live rates pending FIN-81) |
| labor & employment | MoLS | `https://mols.gov.et/law-and-order/` | Law and order | `/am/` | server | strict | `https://mols.gov.et/online-services/` |
| standards | IES | `https://ies.gov.et/online/sales` | Institute of Ethiopian Standards | none | server | strict | `https://motri.gov.et/en/sector/quality-infrastructure-development-and-confirmation-` |
| investment incentives | EIC | `https://investethiopia.gov.et/publications/` | Publications | none (bilingual PDFs) | server | strict | `https://investethiopia.gov.et/why-ethiopia/` |
| import/export permits | MoTRI | `https://motri.gov.et/en/sector/--3` | Trade Integration and Export Promotion | `/am/sector/--3` | server | strict | `https://moi.gov.et` |
| intellectual property | EIPA | `https://eipa.gov.et/application-procedure-2/` | Trademark Application procedure | mixed EN/AM | server | strict | `https://eipa.gov.et/patent/` |
| SME support | EED | `https://manuf-sme.gov.et/national-sme/` | National Manufacturing SME | `/am/መነሻ-ገጽ/` | server | strict | `https://manuf-sme.gov.et/smefp/` |
| e-services portal | eService (MInT) | `https://eservices.gov.et/am` | eService | `/am` default | server (SSR) | relaxed | `https://eservices.gov.et/en` |

Unverified flags for a future pass: `efile.eipo.gov.et` (EIPA e-filing TLS), `etax.mor.gov.et` (login-gated, redirects to `/etaxTrain/faces/login.jspx`), `investinethiopia.gov.et` deep links (SPA, generic titles).

---

## Tool behavior spec (implementation contract for the GitHub port)

Inputs from `Settings`: `TRUSTED_WEB_DOMAINS` (whitelist), `TRUSTED_WEB_REGISTRY` (topic → entries), `TRUSTED_WEB_ALLOW_INSECURE_HTTP` (exception list), `TRUSTED_WEB_CACHE_TTL_SEC` (3600), `TRUSTED_WEB_BODY_CAP` (e.g. 1 MiB read cap), fetch timeout (15s default, 100s for `mols.gov.et`-class slow sites via per-domain timeout metadata).

1. **Selection (strict):** LLM passes `topic` + `url`; URL must be a registry entry for that topic (exact URL match on the entry's `en`/`am` URL). Any other URL → refusal naming the topics available.
2. **Vetting (defense in depth):** scheme must be `https://` unless the domain is on the exception list; domain must be whitelisted; redirect targets re-vetted (same-origin or whitelisted) before following.
3. **Fetch:** httpx with per-entry TLS profile; bounded body read (cap before extraction); best-effort conditional headers against the cache entry.
4. **Extraction:** BeautifulSoup (as today) over the bounded body; if the result has no substantive text (shell HTML, login walls) → `ToolResult` with an explicit "No extractable content (page is client-rendered or login-gated)" note — never fabricate from a shell.
5. **Result shape:** `Source: <label>`, `As of: <RFC3339 UTC>` header lines + content (as today's header, extended). Cached serves append `(cached as of <timestamp>)`.
6. **Cache:** in-process LRU keyed by canonical URL; stores raw body + extracted text + fetched_at; TTL 1h; last-good snapshot survives for stale-serving.
7. **Failure ladder** (per fetch attempt): transient error → one retry (FIN-65 policy) → stale snapshot flagged "cached as of" → per-topic fallback URL (same ladder) → graceful `ToolResult(success=False, result_text="Could not reach <site> as of <time>")`; the LLM answers from KB and states the web source was unreachable.

## Config draft (ai-service `Settings` + YAML registry)

```yaml
# trusted_web_registry.yaml — ported to ai-service config on implementation
domains:            # verified official domains
  - motri.gov.et
  - mor.gov.et
  - mols.gov.et
  - ies.gov.et
  - investethiopia.gov.et
  - investinethiopia.gov.et
  - eipa.gov.et
  - manuf-sme.gov.et
  - moi.gov.et
  - eservices.gov.et
  - etrade.gov.et
  - business.gov.et
allow_insecure_http: [etrade.gov.et, business.gov.et, mor.gov.et, eservices.gov.et]
cache_ttl_sec: 3600
body_cap_bytes: 1048576
timeout_sec: 15
timeout_sec_domains: { mols.gov.et: 100 }
topics:
  business_registration:
    - domain: motri.gov.et
      url: https://motri.gov.et/en/sector/--2
      am_url: https://motri.gov.et/am/sector/--2
      label: Ministry of Trade and Regional Integration
      render: server
      tls: strict
      fallback: https://eservices.gov.et/am
  trade_license: { ... }      # same motri sector page + eservices fallback
  tax_registration: { }       # none curated; KB tax_code + eservices portal; pending FIN-81
  labor:        { domain: mols.gov.et, url: https://mols.gov.et/law-and-order/, am_url: https://mols.gov.et/am/, fallback: https://mols.gov.et/online-services/ }
  standards:    { domain: ies.gov.et, url: https://ies.gov.et/online/sales, fallback: https://motri.gov.et/en/sector/quality-infrastructure-development-and-confirmation- }
  investment:   { domain: investethiopia.gov.et, url: https://investethiopia.gov.et/publications/, fallback: https://investethiopia.gov.et/why-ethiopia/ }
  import_export: { domain: motri.gov.et, url: https://motri.gov.et/en/sector/--3, am_url: https://motri.gov.et/am/sector/--3, fallback: https://moi.gov.et }
  intellectual_property: { domain: eipa.gov.et, url: https://eipa.gov.et/application-procedure-2/, fallback: https://eipa.gov.et/patent/ }
  sme:          { domain: manuf-sme.gov.et, url: https://manuf-sme.gov.et/national-sme/, am_url: https://manuf-sme.gov.et/am/መነሻ-ገጽ/, fallback: https://manuf-sme.gov.et/smefp/ }
  e_services:   { domain: eservices.gov.et, url: https://eservices.gov.et/am, am_url: https://eservices.gov.et/am, fallback: https://eservices.gov.et/en }
```

## Gaps

- `mols.gov.et` intermittently slow from abroad — timeout metadata per domain needed.
- `mor.gov.et` TLS chain incomplete + CSR routes — pending FIN-81; `etax.mor.gov.et` and `efile.eipo.gov.et` re-verify before shipping.
- `business.gov.et` content unverifiable even in-browser; keep whitelisted, never curated.
- Registry drift: no periodic re-verification yet — failure ladder flags dead URLs per fetch; a periodic verify job is a candidate follow-up.
