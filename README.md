# Adisu Serategna — Planning

Product-level planning and documentation repo. Code lives in its own repos (`backend/`, `web/`, `mobile/` under Final-Year-Project-G22); this repo holds everything that is *not* code.

## Conventions

- **Ideas live on Linear** (team *Final Year Project G22*): wayfinder maps and tickets. The ticket is the entry point; the doc is the content.
- **Every doc lives here, committed to `main`.** No doc branches, no doc PRs — if a doc changes, it's committed directly.
- **Repos keep only code-coupled docs** (deployment runbooks, migration checklists that ship with the code).
- **Outdated docs are marked `[DEPRECATED]` or deleted** — never stranded.
- Secrets (`LINEAR_TOKEN`, DB creds) live in `.env` which is gitignored.

## Layout

| Path | Purpose |
|------|---------|
| `docs/agents/` | Issue-tracker config, triage labels, domain conventions |
| `docs/research/` | Research briefs (Amharic fluency, eval methodology), linked from Linear tickets |
| `docs/reference/` | Still-current planning docs migrated out of the code repos |
| `docs/decisions/` | ADRs / PRDs as they graduate from tickets |
| `scripts/linear.sh` | Linear API helper for wayfinding operations |
