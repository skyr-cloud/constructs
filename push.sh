#!/usr/bin/env bash

set -e

if [[ -z "$SKYR_USERNAME" ]]; then
  echo -e "Missing SKYR_USERNAME"
  exit 1
fi

subreponame="${1/\//}"

if [[ ! -d "$subreponame" ]]; then
  echo -e "No such subrepo $subreponame"
  exit 1
fi

echo "Pushing $subreponame"

deployname="$subreponame-$(date +%Y-%m-%d-%H-%M-%S)"
deploydir=".worktrees/$deployname"

git worktree add "$deploydir" "$(git subtree split --prefix="$subreponame")"

echo "Created $deploydir"

cd "$deploydir"

remoteurl="$SKYR_USERNAME@skyr.foo:Constructs/$subreponame"

git remote add "$subreponame" "$remoteurl" 2>/dev/null \
  || git remote set-url "$subreponame" "$remoteurl"
git push --force "$subreponame" HEAD:main
git remote remove "$subreponame"

echo "Pushed $subreponame"
