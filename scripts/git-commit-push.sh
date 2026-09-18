#!/bin/bash
#
# git-commit-push.sh — review changes, write a commit message, commit and push.
#
# Usage:
#   ./git-commit-push.sh                  # run from inside the repo
#   ./git-commit-push.sh /path/to/repo    # or point it at a repo
#
# Walks through: status -> diff -> stage -> confirm -> commit message
# (via $EDITOR, so multi-line messages never break on quoting) -> confirm
# -> commit -> confirm -> push. Every step needs an explicit "y" before
# anything happens; anything else safely stops.

set -uo pipefail

REPO_PATH="${1:-.}"

cd "$REPO_PATH" || { echo "Can't cd into '$REPO_PATH'. Aborting."; exit 1; }

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "'$REPO_PATH' is not a git repository. Aborting."
    exit 1
fi

confirm() {
    # confirm "Question text" -> returns 0 for yes, 1 for anything else
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

REMOTE="origin"
BRANCH="$(git branch --show-current)"

echo "== Repository =="
git remote -v
echo
echo "== Branch =="
echo "$BRANCH"
echo
echo "== Status =="
git status
echo

if [ -z "$(git status --porcelain)" ]; then
    echo "Working tree is clean — nothing to commit."
    exit 0
fi

echo "== Changes (summary) =="
git diff --stat HEAD
echo

if ! confirm "Stage ALL of the above with 'git add -A'?"; then
    echo "Not staging anything. Stage what you want manually, then re-run this script."
    exit 0
fi

git add -A

echo
echo "== Staged for commit =="
git status
echo

if ! confirm "Does this look correct — continue to write a commit message?"; then
    echo "Stopping here. Changes remain staged (run 'git reset' to unstage)."
    exit 0
fi

MSG_FILE="$(mktemp /tmp/commit-msg.XXXXXX)"
trap 'rm -f "$MSG_FILE"' EXIT

EDITOR_CMD="${EDITOR:-nano}"
echo "Opening $EDITOR_CMD to write the commit message."
echo "First line = subject, blank line, then body. Save and quit when done."
echo "Leaving it empty aborts the commit."
"$EDITOR_CMD" "$MSG_FILE"

if [ ! -s "$MSG_FILE" ]; then
    echo "Empty commit message — aborting. Changes remain staged."
    exit 1
fi

echo
echo "== Commit message =="
cat "$MSG_FILE"
echo

if ! confirm "Commit with this message?"; then
    echo "Not committing. Changes remain staged."
    exit 0
fi

git commit -F "$MSG_FILE"

echo
if confirm "Push to $REMOTE/$BRANCH now?"; then
    git push "$REMOTE" "$BRANCH"
else
    echo "Committed locally, not pushed. Run 'git push $REMOTE $BRANCH' when ready."
fi
