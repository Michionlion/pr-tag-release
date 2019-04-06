#!/bin/bash

LATEST_COMMIT_MSG="$(git log -1 --pretty=%B)"
LATEST_VERSION=$(git describe --abbrev=0 --tags)
LATEST_VERSION="${LATEST_VERSION#"v"}"
VERSION_SPLIT=(${LATEST_VERSION//./ })
MAJOR=${VERSION_SPLIT[0]}
MINOR=${VERSION_SPLIT[1]}
PATCH=${VERSION_SPLIT[2]}

echo "Current semver: $MAJOR.$MINOR.$PATCH"
echo "Commit message: $LATEST_COMMIT_MSG"

# detect if this was a PR merge, and what PR it was

# get PR body

# detect and do version change

# create new tag for this PR merge commit, push it

# set TRAVIS_TAG to new tag

# set env var with PR body



