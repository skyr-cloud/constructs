#!/usr/bin/env bash

set -e

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

git push --force skyr HEAD:main

echo "Pushed $subreponame"
