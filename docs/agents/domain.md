# Domain Docs

How the engineering skills should consume this product's domain documentation when exploring the codebase.

## Before exploring, read these

This product is a **multi-repo monorepo**: three separate git repos, each with its own domain glossary. The project root (`final_year_project/`) is not a git repo and holds no `CONTEXT.md`.

| Repo | Context doc | Domain |
|------|-------------|--------|
| `backend/` | `CONTEXT.md` | Core domain: notifications, AI/agentic RAG, permissions, uploads, localization, scheduled alerts, compliance |
| `web/` | `CONTEXT.md` (+ `AGENTS.md` for web-specific operating rules) | Admin portal: modules, conventions, permission integration |
| `mobile/` | `CONTEXT.md` (+ `DESIGN.md` for the design system) | End-user app: guides, journeys, AI coach, community, brand |

Read the context doc of the repo(s) relevant to the topic. The `/domain-modeling` skill keeps each repo's `CONTEXT.md` current and creates ADRs under the relevant repo's `docs/adr/` when decisions are hard to reverse. Product-wide ADRs that span repos may be written under `docs/adr/` at the root.

If any of these files don't exist, proceed silently — the `/domain-modeling` skill creates them lazily.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a test name), use the term as defined in the relevant `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding.
