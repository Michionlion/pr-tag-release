#!/bin/bash

# This script requires Travis CI's env vars
# and a GITHUB_OAUTH_TOKEN env var

DEPLOY_BRANCH=${DEPOY_BRANCH-"^master$"}

VERSION_CHANGE_PREFIX="This PR is a "
VERSION_CHANGE_TYPES=("small (change|update)" "feature" "compatibility[ -]breaking (change|update)" "(non-|un)versioned (change|update)")

LATEST_COMMIT_MSG="$(git log -1 --pretty=%B)"
LATEST_VERSION=$(git describe --abbrev=0 --tags)
LATEST_VERSION="${LATEST_VERSION#"v"}"
VERSION_SPLIT=(${LATEST_VERSION//./ })
MAJOR=${VERSION_SPLIT[0]-0}
MINOR=${VERSION_SPLIT[1]-0}
PATCH=${VERSION_SPLIT[2]-0}

echo "Current semver: $MAJOR.$MINOR.$PATCH"
echo "Commit message:\n---\n$LATEST_COMMIT_MSG\n---\n"

if [[ ! -z "$TRAVIS_TAG" ]]; then
    echo "Current commit ($TRAVIS_COMMIT) already has a tag"
    echo "Don't tag a PR merge commit manually, exiting"
    exit 0
fi

if [[ ! "$TRAVIS_BRANCH" =~ $DEPOY_BRANCH ]]; then
    echo "Not on deploy branch, exiting"
    exit 0
fi

RESULT_FILE="${TRAVIS_COMMIT}_pr_tag.json"

if [[ -z "$GITHUB_OAUTH_TOKEN" ]]; then
    curl https://api.github.com/repos/${TRAVIS_REPO_SLUG}/pulls/${PR_NUM} | jq '[.body, .merged]' > $RESULT_FILE
else
    curl -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" https://api.github.com/repos/${TRAVIS_REPO_SLUG}/pulls/${PR_NUM} | jq '[.body, .merged]' > $RESULT_FILE
fi

if [[ -z "$(cat $RESULT_FILE)" ]]; then
    echo "No result retrieved"
    exit 0
fi

export PR_BODY=$(cat $RESULT_FILE | jq '.[0]')
export MERGED=$(cat $RESULT_FILE | jq '.[1]')

echo "PR_BODY: \n$PR_BODY"

if [[ "$PR_BODY" =~ "${VERSION_CHANGE_PREFIX}${VERSION_CHANGE_TYPES[0]}" ]]; then
    # patch version
    PATCH=$((PATCH+1))
elif [[ "$PR_BODY" =~ "${VERSION_CHANGE_PREFIX}${VERSION_CHANGE_TYPES[1]}" ]]; then
    # minor version
    PATCH="0"
    MINOR=$((MINOR+1))
elif [[ "$PR_BODY" =~ "${VERSION_CHANGE_PREFIX}${VERSION_CHANGE_TYPES[1]}" ]]; then
    # major version
    PATCH="0"
    MINOR="0"
    MAJOR=$((MAJOR+1))
else
    # non-versioned
    echo "Detected non-versioned change, exiting"
    exit 0
fi

if [[ "$MERGED" != "true" ]]; then
    echo "PR is not merged, exiting"
    exit 0
fi

export TRAVIS_TAG="v$MAJOR.$MINOR.$PATCH"

# create tag
git tag $TRAVIS_TAG
git push --tags

export DO_GITHUB_RELEASE="true"

