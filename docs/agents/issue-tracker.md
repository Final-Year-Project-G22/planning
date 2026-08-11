# Issue tracker: Linear (product level) + GitHub (per-repo implementation)

Ideas, efforts, and wayfinder maps/tickets live in **Linear** at the product level — never inside the per-repo trackers. This keeps idea-stage work outside the codebases. Implementation tickets are **ported** into the owning repo's GitHub Issues when they leave the idea stage.

## Product-level (Linear)

- **Team**: `Final Year Project G22` — id `aef9eaf5-b189-4885-91ea-9c68e7ecdbd7`, key `FIN`
- **Project**: `Adisu Serategna: MSME toolkit` — id `a619dcc6-ca6d-4c0f-9b2d-e511440852fb`
- **Auth**: `LINEAR_TOKEN` env var — personal API key from <https://linear.app/settings/api>, stored in the root `.env`. The `linear-cli` npm package is a read-only viewer; `scripts/linear.sh` is the API interface for all operations.
- **Wayfinder labels**: `wayfinder:map`, `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, `wayfinder:task` (team labels).
- **Hierarchy**: map issues are the parent; child tickets are sub-issues via `parentId`.
- **Blocking**: Linear native issue relations, type `blocks` (the only directional enum). "X blocked by Y" = create a `blocks` relation on Y pointing at X. The relation is stored on the blocker only — the frontier query inverts it.

## Implementation (GitHub per repo)

When a ticket is ready to implement:

1. Port it into the owning repo's GitHub Issues: `Final-Year-Project-G22/{backend,web,mobile}` — `gh issue create --title "..." --body "..."` with a `Linear: <identifier>` line pointing back at the source ticket.
2. Work proceeds in that repo (PRs target `dev` and close the GitHub issue).
3. The Linear ticket is marked done with a pointer to the PR.

If the ticket spans multiple repos, port it to the primary repo and reference the others in the body.

## When a skill says "publish to the issue tracker"

Create a Linear issue via `scripts/linear.sh create-issue`.

## When a skill says "fetch the relevant ticket"

`scripts/linear.sh view <id>` (accepts the full UUID; identifiers like FIN-67 resolve via `open`).

## Wayfinding operations

Used by `/wayfinder`. The **map** is one issue labelled `wayfinder:map` with **child** issues as tickets.

- **Map**: `scripts/linear.sh create-issue <team-id> --label wayfinder:map --project <project-id> --title "..." --body "..."` — the Notes / Decisions-so-far / Fog body.
- **Child ticket**: `scripts/linear.sh ensure-label <team-id> wayfinder:<type>` then `create-issue` with that label. Type is one of `research`/`prototype`/`grilling`/`task`.
- **Parent wiring**: `scripts/linear.sh parent <child-id> <map-id>` — makes the child a sub-issue (Linear `parentId`).
- **Blocking**: `scripts/linear.sh relation <blocker-id> <blocked-id> blocks`. A ticket is unblocked when no open issue has a `blocks` relation pointing at it.
- **Frontier**: `scripts/linear.sh open <team-id>` — lists open issues with state, labels, `BLOCKED` marker, parent; drop the BLOCKED ones and any with an assignee; first in creation order wins.
- **Claim**: `scripts/linear.sh assign <issue-id>` (assigns to the token's owner — the dev driving the map). The session's first write.
- **Resolve**: `scripts/linear.sh comment <issue-id> "<answer>"`, then `scripts/linear.sh close <issue-id> "<pointer>"`, then append a context pointer (gist + link) to the map's Decisions-so-far.
