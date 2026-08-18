#!/usr/bin/env bash
# Linear API helper for wayfinding operations.
# Auth: LINEAR_TOKEN env var — personal API key from https://linear.app/settings/api
# Usage: scripts/linear.sh <command> [args...]
#
#   teams                          List teams (id, key, name)
#   projects [--team <id>]         List projects (id, name)
#   labels <team-id>               List labels for a team (id, name)
#   ensure-label <team-id> <name>  Create label if missing; prints its id
#   create-issue <team-id>         Create an issue. Flags: --title, --body,
#     [flags]                        --label <id> (repeatable), --project <id>,
#                                    --assignee <email> (default: token owner)
#   relation <issue-id> <related-id> <type>  Types: blocks|related|duplicates|duplicate.
#                                    Direction: <issue-id> <type> <related-id>.
#                                    For "X blocked by Y": relation <Y-id> <X-id> blocks
#   parent <issue-id> <parent-id>   Make issue a sub-issue of parent
#   assign <issue-id> [email]      Assign issue (default: token owner)
#   comment <issue-id> <body>      Add a comment
#   close <issue-id> [note]        Move to Done state + optional note comment
#   open <team-id>                 List open issues w/ labels, assignee, relations
#   view <identifier-or-id>        Show issue details incl. relations & comments

set -euo pipefail

API="https://api.linear.app/graphql"
TOKEN="${LINEAR_TOKEN:?LINEAR_TOKEN is missing — set it to your Linear personal API key}"

graphql() {
  local query="$1"
  local variables="${2:-}"
  [ -z "$variables" ] && variables='{}'
  curl -s -X POST "$API" \
    -H "Content-Type: application/json" \
    -H "Authorization: $TOKEN" \
    -d "$(jq -nc --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')"
}

die() { echo "error: $*" >&2; exit 1; }

case "${1:-}" in
  teams)
    graphql '{ viewer { id email name } teams { nodes { id key name } } }' \
      | jq -r '"viewer: \(.data.viewer.email // "n/a") (\(.data.viewer.name // "n/a"))\n\(.data.teams.nodes[] | "\(.key)\t\(.id)\t\(.name)")"'
    ;;

  projects)
    shift
    team="" filter=""
    while [ $# -gt 0 ]; do case "$1" in
      --team) team="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac; done
    if [ -n "$team" ]; then
      filter="filter: { team: { id: { eq: \"$team\" } } }"
    fi
    graphql "{ projects(first: 50, $filter) { nodes { id name } } }" \
      | jq -r '.data.projects.nodes[] | "\(.id)\t\(.name)"'
    ;;

  labels)
    [ $# -ge 2 ] || die "usage: labels <team-id>"
    graphql "{ team(id: \"$2\") { labels(first: 100) { nodes { id name } } } }" \
      | jq -r '.data.team.labels.nodes[] | "\(.id)\t\(.name)"'
    ;;

  ensure-label)
    [ $# -ge 3 ] || die "usage: ensure-label <team-id> <name>"
    team="$2" name="$3"
    found=$(graphql "{ team(id: \"$team\") { labels(first: 100) { nodes { id name } } } }" \
      | jq -r --arg n "$name" '.data.team.labels.nodes[] | select(.name == $n) | .id' | head -1)
    if [ -n "$found" ]; then echo "$found"; exit 0; fi
    created=$(graphql 'mutation($team: String!, $name: String!) { labelCreate(input: { teamId: $team, name: $name }) { label { id } } }' \
      "{\"team\": \"$team\", \"name\": \"$name\"}")
    jq -e -r '.data.labelCreate.label.id' <<<"$created" || die "labelCreate failed: $(jq -c .errors <<<"$created")"
    ;;

  create-issue)
    [ $# -ge 2 ] || die "usage: create-issue <team-id> [flags]"
    team="$2"; shift 2
    title="" body="" project="" assignee="" assignee_id=""
    labels=()
    while [ $# -gt 0 ]; do case "$1" in
      --title) title="$2"; shift 2 ;;
      --body) body="$2"; shift 2 ;;
      --label) labels+=("$2"); shift 2 ;;
      --project) project="$2"; shift 2 ;;
      --assignee) assignee="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac; done
    [ -n "$title" ] || die "--title is required"
    if [ -n "$assignee" ]; then
      assignee_id=$(user-id-by-email "$assignee") || die "cannot resolve assignee $assignee"
    fi
    payload=$(jq -nc --arg team "$team" --arg title "$title" --arg body "$body" --arg proj "$project" --arg asg "$assignee_id" \
      '{team: $team, title: $title, body: $body, projectId: (if $proj == "" then null else $proj end), assigneeId: (if $asg == "" then null else $asg end)}')
    payload=$(jq --argjson labs "$(jq -nc --argjson a "$(printf '%s\n' "${labels[@]:-}" | jq -R . | jq -s 'map(select(length > 2))')" '$a')" \
      '. + {labelIds: $labs}' <<<"$payload")
    query='mutation($team: String!, $title: String!, $body: String!, $projectId: String, $assigneeId: String, $labelIds: [String!]) {
      issueCreate(input: { teamId: $team, title: $title, description: $body, projectId: $projectId, assigneeId: $assigneeId, labelIds: $labelIds }) { issue { id identifier title } } }'
    res=$(graphql "$query" "$payload")
    jq -e -r '"\(.data.issueCreate.issue.identifier)\t\(.data.issueCreate.issue.id)\t\(.data.issueCreate.issue.title)"' <<<"$res" \
      || die "issueCreate failed: $(jq -c .errors <<<"$res")"
    ;;

  user-id-by-email)
    [ $# -ge 2 ] || die "usage: user-id-by-email <email>"
    query='query($email: String!) { users(filter: { email: { eq: $email } }, first: 1) { nodes { id email } } }'
    res=$(graphql "$query" "{\"email\": \"$2\"}")
    jq -e -r '.data.users.nodes[0].id' <<<"$res" || die "user not found: $2"
    ;;

  relation)
    [ $# -ge 4 ] || die "usage: relation <issue-id> <related-id> <type>"
    query='mutation($issue: String!, $related: String!, $type: IssueRelationType!) {
      issueRelationCreate(input: { issueId: $issue, relatedIssueId: $related, type: $type }) { success } }'
    vars="{\"issue\": \"$2\", \"related\": \"$3\", \"type\": \"$4\"}"
    res=$(graphql "$query" "$vars")
    jq -e -r '.data.issueRelationCreate.success' <<<"$res" | grep -q true || die "relation failed: $(jq -c .errors <<<"$res")"
    echo "relation $4: $2 <- $3"
    ;;

  assign)
    [ $# -ge 2 ] || die "usage: assign <issue-id> [email]"
    email="${3:-}"
    if [ -z "$email" ]; then
      email=$(graphql '{ viewer { email } }' | jq -r '.data.viewer.email')
    fi
    user_id=$("$0" user-id-by-email "$email")
    query='mutation($issue: String!, $user: String!) {
      issueUpdate(id: $issue, input: { assigneeId: $user }) { issue { id assignee { email } } } }'
    res=$(graphql "$query" "{\"issue\": \"$2\", \"user\": \"$user_id\"}")
    jq -e -r '.data.issueUpdate.issue.assignee.email // "unassigned"' <<<"$res" || die "assign failed: $(jq -c .errors <<<"$res")"
    ;;

  comment)
    [ $# -ge 3 ] || die "usage: comment <issue-id> <body>"
    query='mutation($issue: String!, $body: String!) {
      commentCreate(input: { issueId: $issue, body: $body }) { comment { id } } }'
    vars=$(jq -nc --arg i "$2" --arg b "$3" '{issue: $i, body: $b}')
    res=$(graphql "$query" "$vars")
    jq -e '.data.commentCreate.comment.id' <<<"$res" >/dev/null || die "comment failed: $(jq -c .errors <<<"$res")"
    echo "commented $2"
    ;;

  close)
    [ $# -ge 2 ] || die "usage: close <issue-id> [note]"
    query='mutation($issue: String!) {
      issueUpdate(id: $issue, input: { stateId: null }) { issue { id } } }'
    # Resolve "Done" state for the issue's team via its workflow
    team_id=$(graphql "{ issue(id: \"$2\") { team { id } } }" | jq -r '.data.issue.team.id')
    done_state=$(graphql "{ team(id: \"$team_id\") { states { nodes { id name type } } } }" \
      | jq -r '.data.team.states.nodes[] | select(.type == "completed") | .id' | head -1)
    [ -n "$done_state" ] || die "no completed state found for team $team_id"
    res=$(graphql 'mutation($issue: String!, $state: String!) {
      issueUpdate(id: $issue, input: { stateId: $state }) { issue { id state { name } } } }' \
      "{\"issue\": \"$2\", \"state\": \"$done_state\"}")
    jq -e -r '"closed: \(.data.issueUpdate.issue.state.name)"' <<<"$res" || die "close failed: $(jq -c .errors <<<"$res")"
    if [ $# -ge 3 ]; then "$0" comment "$2" "$3" >/dev/null; fi
    ;;

  open)
    [ $# -ge 2 ] || die "usage: open <team-id>"
    q='query($team: String!){ team(id:$team){ issues(first:100, orderBy:createdAt){ nodes{ identifier title state{name} assignee{email} labels{nodes{name}} parent{identifier} } } } }'
    relq='{ issues(first: 100) { nodes { state { type } relations { nodes { type relatedIssue { identifier } } } } } }'
    issues_json=$(graphql "$q" "{\"team\": \"$2\"}")
    rels_json=$(graphql "$relq" "{}")
    jq -r --slurpfile rels <(printf '%s' "$rels_json") '
      ([ $rels[0].data.issues.nodes[] | select(.state.type != "completed") | .relations.nodes[] | select(.type == "blocks") | .relatedIssue.identifier ] | unique) as $blocked
      | .data.team.issues.nodes[]
      | [ .identifier, .state.name, (if .assignee then .assignee.email else "-" end),
          ([.labels.nodes[].name] | join(",")),
          (.identifier as $i | if (any($blocked[]; . == $i)) then "BLOCKED" else "-" end),
          (.parent.identifier // "-"),
          .title ] | @tsv' <<<"$issues_json"
    ;;

  parent)
    [ $# -ge 3 ] || die "usage: parent <issue-id> <parent-id>"
    query='mutation($issue: String!, $parent: String!) {
      issueUpdate(id: $issue, input: { parentId: $parent }) { issue { id parent { identifier } } } }'
    res=$(graphql "$query" "{\"issue\": \"$2\", \"parent\": \"$3\"}")
    jq -e -r '"parented: \(.data.issueUpdate.issue.parent.identifier // "none")"' <<<"$res" || die "parent failed: $(jq -c .errors <<<"$res")"
    ;;

  view)
    [ $# -ge 2 ] || die "usage: view <identifier-or-id>"
    query='query($id: String!) { issue(id: $id) {
      identifier title description state { name } assignee { email } labels { nodes { name } }
      relations { nodes { type relatedIssue { identifier title state { name } } } }
      comments { nodes { body createdAt } } } }'
    res=$(graphql "$query" "{\"id\": \"$2\"}")
    jq -e '.data.issue' <<<"$res" >/dev/null || { echo "try: linear view <full-id> (identifiers need the id)"; die "$(jq -c .errors <<<"$res")"; }
    jq -r '
      "ID: \(.data.issue.identifier)\nState: \(.data.issue.state.name)  Assignee: \(.data.issue.assignee.email // "-")\nLabels: \([.data.issue.labels.nodes[].name] | join(", "))\n\n\(.data.issue.description)\n\nRELATIONS:" ,
      (.data.issue.relations.nodes[] | "  \(.type): \(.relatedIssue.identifier) [\(.relatedIssue.state.name)] \(.relatedIssue.title)"),
      "\nCOMMENTS:", (.data.issue.comments.nodes[] | "---\n\(.body)")' <<<"$res"
    ;;

  *) die "unknown command: ${1:-}. Commands: teams projects labels ensure-label create-issue relation assign comment close open view" ;;
esac
