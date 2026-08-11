# Research: Amharic fluency and retrieval (FIN-67)

**Ticket:** FIN-67 · **Repo:** Adisu Serategna backend (`ai-service` + Postgres/pgvector AI DB) · **Date:** 2025-XX-XX

**Citation legend**
- `[repo:path]` — claim grounded directly in repo source (verifiable by reading the file).
- `[doc:URL]` — claim from provider documentation (official URL). **Verification status:** this run had no web access (web_search tool unavailable), so doc URLs are from established documentation knowledge and **must be live-verified before the brief is used externally** (see Gaps).
- `[ver-flag]` — specific fact inside a doc-cited claim that needs explicit verification.

---

## Summary

1. **LLM answer quality:** The current default LLM — Cohere **Command A (`command-a-03-2025`)** — is not documented as supporting Amharic in Cohere's official supported-language documentation, while **Google Gemini (2.5 Flash/Pro) officially lists Amharic** among its 100+ supported languages. Gemini 2.5 Flash is also ~5× cheaper on input and ~3× cheaper on output than Command A, and the repo's `GeminiLLMAdapter` already implements native function calling (required by the default agentic strategy). **Recommendation: make Gemini 2.5 Flash the default LLM, or route by locale (am → Gemini, en → Cohere).**
2. **Retrieval:** The embedding model in use — Cohere **`embed-multilingual-v3.0`** (1024-dim) — is a genuine multilingual model covering 100+ languages including Amharic, so semantic retrieval of Fidel-script content is expected to work; query/document `input_type` asymmetry is handled correctly. The **"BM25" leg is PostgreSQL full-text search with the `simple` configuration** (`plainto_tsquery('simple')` + `ts_rank_cd` over a persisted `to_tsvector('simple', chunk_text)` column): no Amharic stemming, exact surface-word matching only, all query terms ANDed, and Latin-script transliterations never match Fidel tokens — so the lexical leg is weak for Amharic. Additional structural issues: retrieval in both Ask strategies is **language-gated** (Amharic conversation ⇒ only `language='am'` chunks), the **intent classifier uses English-only seed queries**, and all embedding columns are **hardcoded `Vector(1024)`**, which blocks switching to 768-dim Gemini embeddings without a migration.

---

## 2. Current stack (repo-grounded)

| Layer | In use (defaults) | Where |
|---|---|---|
| LLM provider / model | Cohere / `command-a-03-2025` | `ai-service/app/config.py` (`LLM_PROVIDER="cohere"`, `COHERE_LLM_MODEL="command-a-03-2025"`) |
| Gemini fallback model | `gemini-2.5-flash` (Vertex default `GEMINI_USE_VERTEX=True`) | `ai-service/app/config.py` |
| Embedding provider / model | Cohere / `embed-multilingual-v3.0`, 1024 dims | `ai-service/app/config.py` (`EMBEDDING_PROVIDER="cohere"`, `COHERE_EMBEDDING_MODEL="embed-multilingual-v3.0"`); `ai-service/infrastructure/embeddings/__init__.py` (dims default 1024) |
| Embedding index | pgvector `Vector(1024)`, HNSW `vector_cosine_ops` | `ai-service/infrastructure/database/models_sqlalchemy.py` (`DocumentChunk.embedding`, `ix_document_chunks_embedding_hnsw`) |
| "BM25" | PostgreSQL FTS, `simple` config, `ts_rank_cd`, GIN index | `ai-service/infrastructure/database/repositories/knowledge_repository.py` (`search_bm25`); `models_sqlalchemy.py` (`content_tsvector` computed column) |
| Retrieval merge | vector-first dedupe, max 12 hits, top_k 8/8 | `ai-service/core/usecases/strategies/simple_ask.py` & `agentic_ask.py` (`_merge_and_dedupe_hits`, `core/usecases/defaults.py`) |
| Agent strategy | Agentic ReAct default (`AI_AGENTIC_ENABLED=True`, max 5 iterations) | `ai-service/app/config.py`; `ai-service/core/usecases/strategies/agentic_ask.py` |
| Intent classifier | cosine vs 2 centroids from **English-only** seed queries, threshold 0.6 | `ai-service/infrastructure/tools/intent_classifier.py`; `ai-service/app/config.py` (`AI_INTENT_SEED_QUERIES_*`) |
| Reranker | none wired (flashrank declared in `ai-service/pyproject.toml` but no adapter/tool uses it) | `ai-service/app/container.py` |
| AI DB | `pgvector/pgvector:pg18` (Postgres 18) | `docker-compose.yml` |

---

## 3. Findings

### A. LLM provider/config for Amharic answer quality

1. **Current default is Cohere Command A.** `LLM_PROVIDER="cohere"` / `COHERE_LLM_MODEL="command-a-03-2025"` in `ai-service/app/config.py`; the adapter calls the v2 `/v2/chat` endpoint with OpenAI-style tool definitions (`ai-service/infrastructure/llm/cohere.py`). The agentic (ReAct) strategy is the default and requires native tool calling, which both adapters implement.

2. **Cohere's Command family does not officially list Amharic as a supported language.** Cohere's official supported-languages documentation lists the Command models' supported languages (Command A covers a subset of ~23 languages: Arabic, Chinese (Simplified), Czech, Dutch, English, French, German, Greek, Hebrew, Hindi, Hungarian, Indonesian, Italian, Japanese, Korean, Malay, Norwegian, Polish, Portuguese, Romanian, Russian, Slovak, Spanish, Swedish, Turkish, Ukrainian, Vietnamese) — **Amharic is not among them** `[doc:https://docs.cohere.com/docs/supported-languages]` `[ver-flag: exact list/count]`. The model may still emit some Amharic text (large multilingual models generalize), but there is **no official quality/support claim for Amharic**, which is a direct risk to the product promise "You speak both English and Amharic fluently" (`ai-service/app/config.py` `AI_PERSONA_SYSTEM_PROMPT`; `ai-service/prompts/_persona.j2`).
   - **Severity: HIGH** — core user-facing promise for the `am` locale depends on a model without documented Amharic support.

3. **Gemini officially supports Amharic.** Google's Gemini API model documentation and the Gemini model cards list Amharic among the 100+ supported languages for Gemini 1.5/2.0/2.5 family models `[doc:https://ai.google.dev/gemini-api/docs/models]` `[doc:https://deepmind.google/models/gemini/]` `[doc:https://storage.googleapis.com/deepmind-media/Model-Cards/Gemini-2.5-Flash-Model-Card.pdf]` `[ver-flag: exact language list per model card]`. The repo's `GeminiLLMAdapter` (`ai-service/infrastructure/llm/gemini.py`) already supports both Vertex (`:generateContent`/`:streamGenerateContent`) and API-key modes with `functionDeclarations` tool calling, so switching is a config change, not new code.

4. **Cost comparison favors Gemini.** Official pricing pages: Cohere Command A ≈ **$1.50/M input, $7.50/M output** `[doc:https://docs.cohere.com/pricing]`; Gemini 2.5 Flash ≈ **$0.30/M input (≤200k context), $2.50/M output**, Gemini 2.5 Pro ≈ $1.25/M input, $10/M output `[doc:https://ai.google.dev/gemini-api/docs/pricing]`. At the repo's default of 1024 max output tokens and 32768 max prompt length (`ai-service/core/usecases/defaults.py`), Gemini 2.5 Flash is ~5× cheaper on input and ~3× cheaper on output than Command A, plus a 1M-token context window vs Command A's 256k `[ver-flag: exact current prices]`.

5. **Tool-calling parity.** Both adapters implement function calling; the agentic strategy (`agentic_ask.py`) renders system prompt, calls `llm_port.generate(..., tools=...)`, executes tool calls via the Tool Registry, and loops. No provider-specific change is required to run the agentic strategy on Gemini. Caveat: `GEMINI_USE_VERTEX=True` by default (`app/config.py`) requires a Google service account / `GOOGLE_APPLICATION_CREDENTIALS`; the API-key path (`GEMINI_USE_VERTEX=false` + `GEMINI_API_KEY`) is the low-friction option for a trial.

6. **Intent classifier is English-only — hurts Amharic pre-fetch (performance, not correctness).** Centroids are computed from `AI_INTENT_SEED_QUERIES_KNOWLEDGE` / `_PERSONAL`, all English (`ai-service/app/config.py`; `ai-service/infrastructure/tools/intent_classifier.py`). An Amharic query embedded against English centroids with threshold 0.6 will often classify as MIXED, skipping tool pre-fetch (one extra ReAct iteration). The agentic loop still exposes all tools, so answers remain correct.
   - **Severity: MEDIUM** (latency/cost per Amharic query, no wrong answers).

### B. Retrieval: embeddings + "BM25" (Postgres FTS) for Fidel script

7. **Embedding model in use is genuinely multilingual.** `COHERE_EMBEDDING_MODEL="embed-multilingual-v3.0"` (`ai-service/app/config.py`), 1024 dims (`ai-service/infrastructure/embeddings/__init__.py`), served through `ai-service/infrastructure/embeddings/cohere.py` (v1 `/v1/embed`, batch 96, input_type `search_document`/`search_query`, rate-limit retry). Cohere documents embed-multilingual-v3.0 as supporting 100+ languages, Amharic included `[doc:https://docs.cohere.com/docs/embed]` `[ver-flag: confirm Amharic in the official language list]`. The correct asymmetric `input_type` usage (query=`search_query`, docs=`search_document`) is implemented, which matters for retrieval quality with this model. **Conclusion: the embedding leg is appropriate for Amharic; no change strictly required.**

8. **"BM25" is PostgreSQL full-text search with `simple` config — the lexical leg is weak for Amharic.** `search_bm25` (`ai-service/infrastructure/database/repositories/knowledge_repository.py`) runs `plainto_tsquery('simple', query)` and ranks with `ts_rank_cd(content_tsvector, ts_query)` over the persisted computed column `to_tsvector('simple', chunk_text)` (`ai-service/infrastructure/database/models_sqlalchemy.py`). Consequences for Fidel script:
   - **No Amharic dictionary/stemmer exists in PostgreSQL.** The predefined text-search configurations are `simple` plus 15 European languages (danish, dutch, english, finnish, french, german, hungarian, italian, norwegian, portuguese, romanian, russian, spanish, swedish, turkish) `[doc:https://www.postgresql.org/docs/current/textsearch-controls.html]`. `simple` only lowercases and splits on word boundaries — it does **no stemming**.
   - **Exact surface-word matching only.** Amharic is a morphologically rich Semitic language: inflected verb forms and plural/possessive suffix variants of a root do not match each other (e.g., query ሰነድ vs ሰነዶች, or መስጠት vs ሰጠ). For Amharic IR this is the classic stemming gap `[doc:https://www.postgresql.org/docs/current/textsearch-controls.html]` + academic background: Argaw & Asker, "Amharic-English Information Retrieval" (2007) `[ver-flag]`.
   - **`plainto_tsquery` ANDs all query terms** — if any single token has no exact match (morphological variant, typo, punctuation variant), the whole query can return zero lexical hits `[doc:https://www.postgresql.org/docs/current/functions-textsearch.html]`.
   - **Transliterated queries never match.** A user typing Latin-script Amharic ("sened", "ye nigid fikad") yields tokens that can never match Fidel-script tsvector entries; the `simple` parser has no script normalization.
   - **Tokenization itself is not the problem.** Ethiopic letters (U+1200–U+137F, category Lo) tokenize as words and Ethiopic punctuation (፡ U+1361, ። U+1362, etc., category Po) acts as a delimiter, and Amharic is space-separated — so word splitting works; the gap is morphological/typographic matching, not splitting.
   - **Severity: MEDIUM-HIGH** for Amharic retrieval — mitigated by the vector leg (finding 7) but the hybrid merge simply concatenates vector hits first (`_merge_and_dedupe_hits`, `simple_ask.py`/`agentic_ask.py`), so weak BM25 reduces recall for exact-phrase and transliterated queries.

9. **Retrieval is language-gated in both Ask strategies — risk of zero results.** `_retrieve_context` in `simple_ask.py` and `agentic_ask.py` builds `SearchFilters(language=command.language, only_active=True)`; the conversation locale comes from core-backend via gRPC `request.language` (`ai-service/infrastructure/rpc/services/inference_service.py`). An Amharic conversation therefore only retrieves chunks tagged `language='am'` — if the knowledge base is predominantly English-ingested (many Ethiopian proclamations/guides are in English), Amharic queries can legitimately return **no context**. Note the inconsistency: the `search_knowledge_base` tool uses `SearchFilters()` with no language filter (`ai-service/infrastructure/tools/local/search_knowledge_base.py`, description: "English or Amharic"), so agentic answers depend on which path the LLM takes.
   - **Severity: MEDIUM-HIGH** (directly reduces grounded-answer quality for Amharic users; impact depends on actual `am`-tagged corpus size — unknown from repo).

10. **Schema constraint: embedding columns are hardcoded `Vector(1024)`.** `DocumentChunk.embedding` and `AIChatMessage.query_embedding` (`ai-service/infrastructure/database/models_sqlalchemy.py`). Switching embeddings to Gemini `text-multilingual-embedding-002` (768-dim) or `multilingual-e5-base` (768-dim) requires a migration + full re-embed; **`multilingual-e5-large` (1024-dim) and the current Cohere model fit the schema as-is** `[doc:https://huggingface.co/intfloat/multilingual-e5-large]` `[ver-flag: dims]`. The `EmbeddingProfile` entity already supports multi-model indexing (only_active_profile filter) — a clean path for a side-by-side eval.
    - **Severity: MEDIUM** (blocks embedding swaps without migration).

11. **Ollama default is unsuitable for Amharic.** `OLLAMA_EMBEDDING_MODEL="nomic-embed-text"` (`app/config.py`) — an English-centric model; **do not** use the Ollama path for Amharic retrieval. `multilingual-e5` (via Ollama or a hosted endpoint) is the relevant self-hosted alternative: 100-language CC100/XLM-R lineage, Amharic included `[doc:https://huggingface.co/intfloat/multilingual-e5-large]` `[ver-flag]`.

12. **Chunk sizing uses tiktoken `cl100k_base`** (`ai-service/infrastructure/chunking/structural.py`), which byte-level-BPEs rare-script text: Amharic token counts are inflated vs the provider tokenizers (only affects chunk-size budgeting, not retrieval).

13. **No reranker in the pipeline.** `flashrank>=0.2.0` is declared (`ai-service/pyproject.toml`) but no reranker is wired (`ai-service/app/container.py`, tools, strategies). FlashRank's ms-marco MiniLM models are English-centric; a reranker is unlikely to add Amharic value — prefer fixing recall (findings 8–9).

---

## 4. Recommendation

Ordered by impact; each is a config change or small, contained code change.

1. **Make Gemini 2.5 Flash the default LLM (or route by locale).**
   - Quick path (config only): `LLM_PROVIDER=gemini`, `GEMINI_LLM_MODEL=gemini-2.5-flash`, `GEMINI_USE_VERTEX=false`, set `GEMINI_API_KEY`. Agentic ReAct keeps working via `GeminiLLMAdapter` function calling.
   - Better path (small code change): per-locale provider selection in `AskAIUseCase`/container (`am` → Gemini, `en` → Cohere) using both existing adapters; keeps the current Cohere behavior for English while Amharic gets documented support.
   - Keep `temperature=0.2` (grounded-answer mode) and the citation/unknown-handling guardrails unchanged.
   - **Severity addressed: HIGH (finding 2).**

2. **Keep Cohere `embed-multilingual-v3.0` embeddings (no change).** It is Amharic-capable, 1024-dim (fits the schema), and the adapter already does correct `search_query`/`search_document` usage. Optionally evaluate Gemini `text-multilingual-embedding-002` via a new `EmbeddingProfile` row; adopt only with an explicit `Vector(768)` migration + re-embed of the KB. Do **not** switch to `nomic-embed-text`.

3. **Fix the lexical (FTS) leg for Fidel script.**
   - Add `pg_trgm` GIN index on `document_chunks.chunk_text` and use trigram similarity as a third retrieval leg (or fallback) — trigram matching is script-agnostic and tolerates morphological surface variants and minor typos in Fidel.
   - Index an **Amharic-normalized copy** of chunk text (canonicalize Ethiopic punctuation; optionally add a Latin-transliteration copy) and normalize queries the same way, so transliterated queries ("sened") match Fidel documents. This is the standard pragmatic fix given PG ships no Amharic dictionary.
   - Keep `simple`-config tsvector as a low-weight signal for Amharic; rely on vector + trigram as the primary legs. (Postgres 18 — `pgvector/pgvector:pg18` in `docker-compose.yml` — has no Amharic FTS config either.)
   - **Severity addressed: MEDIUM-HIGH (finding 8).**

4. **De-gate or fallback the language filter in strategy retrieval.** Align `_retrieve_context` (`simple_ask.py`, `agentic_ask.py`) with the language-agnostic `search_knowledge_base` tool: either drop the `language` filter, or run a fallback search without the filter when the filtered pass returns below a threshold (e.g., < 3 hits). **Severity addressed: MEDIUM-HIGH (finding 9).**

5. **Add Amharic seed queries to the intent classifier.** Extend `AI_INTENT_SEED_QUERIES_KNOWLEDGE` / `_PERSONAL` (`app/config.py`, env-configurable) with 10–20 Amharic equivalents (e.g., የንግድ ፈቃድ እንዴት ማግኘት ይቻላል) so Amharic knowledge queries pre-fetch tools. **Severity addressed: MEDIUM (finding 6).**

6. **Build an Amharic eval set before/after the switch.** Neither provider publishes Amharic-specific LLM quality benchmarks, so "best Amharic answer quality" must be decided empirically: 30–50 real Amharic Q&A pairs over actual KB documents, scoring (a) retrieval recall@8 (does the right chunk surface?) and (b) answer fluency/accuracy by a fluent Amharic reviewer. Run once on Cohere, once on Gemini 2.5 Flash (and optionally 2.5 Pro for legal/tax questions where the system prompt mandates grounded citation).

7. **If Gemini embeddings are adopted later:** migration `Vector(1024)` → `Vector(768)` on `document_chunks.embedding` + `ai_chat_messages.query_embedding`, re-embed all active chunks, register a new `EmbeddingProfile`.

---

## 5. Sources

- **Kept (primary, official):**
  - Cohere supported languages — https://docs.cohere.com/docs/supported-languages (Command family language list; basis for "no official Amharic support" finding) — **verify live**
  - Cohere Embed docs — https://docs.cohere.com/docs/embed (embed-multilingual-v3.0, 100+ languages) — **verify live**
  - Cohere pricing — https://docs.cohere.com/pricing (Command A rates) — **verify live**
  - Google Gemini API models — https://ai.google.dev/gemini-api/docs/models (100+ languages incl. Amharic) — **verify live**
  - Google Gemini API pricing — https://ai.google.dev/gemini-api/docs/pricing (2.5 Flash/Pro rates) — **verify live**
  - Google DeepMind Gemini 2.5 Flash model card — https://storage.googleapis.com/deepmind-media/Model-Cards/Gemini-2.5-Flash-Model-Card.pdf (language coverage) — **verify live**
  - Vertex AI text embeddings — https://cloud.google.com/vertex-ai/generative-ai/docs/embeddings/get-text-embeddings (text-multilingual-embedding-002, languages/dims) — **verify live**
  - Microsoft multilingual-e5 model card — https://huggingface.co/intfloat/multilingual-e5-large (100 languages, dims) — **verify live**
  - PostgreSQL FTS docs — https://www.postgresql.org/docs/current/textsearch-controls.html and https://www.postgresql.org/docs/current/functions-textsearch.html (predefined configs incl. `simple`; `plainto_tsquery` AND semantics)
- **Kept (repo primary):** `ai-service/app/config.py`, `ai-service/infrastructure/embeddings/{__init__,cohere,gemini,ollama}.py`, `ai-service/infrastructure/llm/{cohere,gemini}.py`, `ai-service/infrastructure/database/{models_sqlalchemy.py,repositories/knowledge_repository.py}`, `ai-service/core/usecases/strategies/{simple_ask,agentic_ask}.py`, `ai-service/infrastructure/tools/{local/search_knowledge_base.py,intent_classifier.py}`, `ai-service/infrastructure/chunking/structural.py`, `ai-service/app/container.py`, `docker-compose.yml`.
- **Dropped:** none — no secondary write-ups were used (per ticket instruction).

---

## 6. Gaps

1. **Live web verification was not possible in this run** (web_search tool unavailable). Every `[doc:]` claim and `[ver-flag]` must be confirmed against the official URLs before external use — particularly (a) whether Cohere's supported-language page still excludes Amharic for Command A, (b) current pricing, (c) Amharic in the Gemini model-card language list, (d) Amharic in Cohere embed's official language list, (e) multilingual-e5's exact language list/dims. This is a ~30-minute manual verification pass or a re-run with web access.
2. **No Amharic-specific quality benchmarks exist from either provider** for LLM answer quality — the recommendation leans on official language-support claims + cost; empirical eval (Recommendation 6) is required to confirm.
3. **Unknown corpus composition:** whether the KB actually contains `language='am'` chunks (and how many) determines the real severity of the language-gating finding (9). Inspect `knowledge_documents.language` distribution in the `adisu_ai` DB.
4. **Transliteration normalization** (Recommendation 3b) has no off-the-shelf library verified for this repo's language stack (Python 3.11); options (e.g., a curated Fidel↔Latin map for Amharic business vocabulary) need prototyping.
5. **Suggested next step:** run the eval set (Recommendation 6) on Cohere vs Gemini 2.5 Flash, then flip `LLM_PROVIDER` per Recommendation 1 and re-run to confirm end-to-end.

---

## Verification pass (live web, 2026-08-11)

Live-fetched against official sources. Corrections and confirmations:

| # | Brief claim | Verdict | Live source |
|---|-------------|---------|-------------|
| A1 | Cohere Command family documents **no** Amharic support (HIGH severity) | **CONTRADICTED — severity drops to MEDIUM.** Cohere's Supported Languages page now lists **104 languages including Amharic (`am`)**. The rendered page states no per-model restriction; the brief's ~23-language list reflects an older version of the docs. Empirical Amharic quality is still unmeasured — docs support ≠ fluent output. | https://docs.cohere.com/docs/supported-languages |
| A2 | Gemini 2.5 Flash $0.30/M input, $2.50/M output | **CONFIRMED** | https://ai.google.dev/gemini-api/docs/pricing |
| A3 | Gemini 2.5 Pro $1.25/M input, $10/M output | **CONFIRMED** | same as A2 |
| A4 | Recommend Gemini 2.5 Flash as default | **OUTDATED.** Current lineup (live): **gemini-3.6-flash $1.50/$7.50**, gemini-3.5-flash $1.50/$9.00, **gemini-3.5-flash-lite $0.30/$2.50** ("most cost-efficient GA model, optimized for high-volume agentic tasks"), gemini-3.1-flash-lite $0.25/$1.50, gemini-3-flash-preview $0.50/$3.00. Gemini 2.0 is deprecated and shut down June 1 2026. Recommendation to update: prefer the current cost-efficient GA agentic pick (**3.5-flash-lite**) or 3.6-flash for quality; 2.5-flash still available at the same price. | https://ai.google.dev/gemini-api/docs/pricing |
| A5 | Cohere Command A ≈ $1.50/$7.50 | **UNCONFIRMED on the live pricing page.** cohere.com/pricing lists only legacy models (Command $1.00/$2.00, Command-light $0.30/$0.60, Command R 03-2024 $0.50/$1.50, Command R+ 04-2024 $3.00/$15.00, Command R+ 08-2024 $2.50/$10.00, Aya Expanse $0.50/$1.50). Command A is absent; the $1.50/$7.50 figure likely stems from the Mar-2025 announcement. Current Command A pricing must be confirmed with Cohere before cost decisions. | https://cohere.com/pricing |
| A6 | embed-multilingual-v3.0, 1024-dim, 100+ languages | **CONFIRMED (repo) / PARTIAL (docs).** Model name + 1024-dim verified in `ai-service/app/config.py`; Cohere's embed docs page is JS-rendered (not machine-readable), but 100+ language support is consistent with the languages page. | repo + https://docs.cohere.com/docs/supported-languages |
| A7 | multilingual-e5-large: 1024-dim, 100+ languages, Amharic | **CONFIRMED** (1024, 100+ languages, Amharic listed) | https://huggingface.co/intfloat/multilingual-e5-large |
| A8 | PostgreSQL ships no Amharic FTS config; `simple` is the fallback | **CONFIRMED** (predefined configs are `simple` + European languages only) | https://www.postgresql.org/docs/current/textsearch-controls.html |
| A9 | `plainto_tsquery` ANDs all terms | **CONFIRMED** (stable documented behavior) | https://www.postgresql.org/docs/current/functions-textsearch.html |
| A10 | Gemini text-multilingual-embedding-002 = 768-dim | **UNVERIFIED** (Google Cloud docs JS-rendered). Plausible; verify in the Vertex AI console before relying on dims for a migration. | https://cloud.google.com/vertex-ai/generative-ai/docs/embeddings/get-text-embeddings |
| A11 | "Gemini supports Amharic (100+ languages)" | **NOT machine-verifiable this pass.** The cited DeepMind 2.5 Flash model-card PDF is DEAD (storage.googleapis returns NoSuchKey); ai.google.dev and cloud.google.com docs are JS-rendered with no server-side Amharic mention. Treat as widely-documented-but-unverified; the strongest live evidence is Google's own "100+ languages" marketing + pricing page model list. | n/a (dead URL) |

**Net effect on recommendations:**
- The **HIGH-severity** "Cohere has no Amharic" risk is removed — Cohere now documents Amharic. The decision between Cohere and Gemini should now be driven by *empirical* Amharic quality (Recommendation 6 in the brief — the eval set) rather than documentation, plus cost.
- The provider-switch recommendation should target the **current Gemini lineup** (3.5-flash-lite for cost/agentic, 3.6-flash for quality) rather than 2.5-flash.
- Embedding/retrieval findings (FTS weakness, language-gating, transliteration gap, pg_trgm, Amharic normalization) are **unchanged** — they were repo-grounded, not doc-dependent.
