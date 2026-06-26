#!/bin/bash
# Kin workspace backup script. Run during PHOENIX protocol.

set -euo pipefail

WORKSPACE="/Users/wealthhealth_admin/.openclaw/workspace-kin"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

cd "$WORKSPACE"

git add -A

TODAY=$(date '+%Y-%m-%d')
if [ -f "memory/$TODAY.md" ]; then
  git add -f "memory/$TODAY.md"
fi

if compgen -G "memory/sessions/$TODAY-*.md" > /dev/null; then
  git add -f memory/sessions/"$TODAY"-*.md
fi

if git diff --cached --quiet; then
  echo "No changes to commit at $TIMESTAMP"
  git pull --rebase origin master
  exit 0
fi

git commit -m "backup: $TIMESTAMP"
git pull --rebase origin master
git push origin master

echo "Backup complete at $TIMESTAMP"
