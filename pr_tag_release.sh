#!/bin/bash

# This script requires Travis CI's env vars
# and a GITHUB_OAUTH_TOKEN env var

DEPLOY_BRANCH=${DEPOY_BRANCH-"^master$"}

VERSION_CHANGE_PREFIX="This PR is a "
VERSION_CHANGE_TYPES=("small (change|update)" "feature" "compatibility[ -]breaking (change|update)")

LATEST_COMMIT_MSG="$(git log -1 --pretty=%B)"
LATEST_VERSION=$(git describe --abbrev=0 --tags)
LATEST_VERSION="${LATEST_VERSION#"v"}"
VERSION_SPLIT=(${LATEST_VERSION//./ })
MAJOR=${VERSION_SPLIT[0]-0}
MINOR=${VERSION_SPLIT[1]-0}
PATCH=${VERSION_SPLIT[2]-0}

echo -e "Current semver: $MAJOR.$MINOR.$PATCH"
echo -e "Commit message:\n---\n$LATEST_COMMIT_MSG\n---\n"

if [[ ! -z "$TRAVIS_TAG" ]]; then
    echo -e "Current commit ($TRAVIS_COMMIT) already has a tag"
    echo -e "Don't tag a PR merge commit manually, exiting"
    sleep 0.5
    exit 0
fi

if [[ ! "$TRAVIS_BRANCH" =~ $DEPOY_BRANCH ]]; then
    echo -e "Not on deploy branch, exiting"
    sleep 0.5
    exit 0
fi

RESULT_FILE="${TRAVIS_COMMIT}_pr_tag.json"

if [[ -z "$GITHUB_OAUTH_TOKEN" ]]; then
    curl https://api.github.com/repos/${TRAVIS_REPO_SLUG}/pulls/${PR_NUM} | jq '[.body, .merged]' > $RESULT_FILE
else
    curl -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" https://api.github.com/repos/${TRAVIS_REPO_SLUG}/pulls/${PR_NUM} | jq '[.body, .merged]' > $RESULT_FILE
fi

if [[ -z "$(cat $RESULT_FILE)" ]]; then
    echo -e "No result retrieved"
    sleep 0.5
    exit 0
fi

export PR_BODY=$(cat $RESULT_FILE | jq '.[0]')
export MERGED=$(cat $RESULT_FILE | jq '.[1]')

echo -e "PR_BODY: \n$PR_BODY"

if [[ "$PR_BODY" =~ "${VERSION_CHANGE_PREFIX}${VERSION_CHANGE_TYPES[0]}" ]]; then
    # patch version
    PATCH=$((PATCH+1))
elif [[ "$PR_BODY" =~ "${VERSION_CHANGE_PREFIX}${VERSION_CHANGE_TYPES[1]}" ]]; then
    # minor version
    PATCH="0"
    MINOR=$((MINOR+1))
elif [[ "$PR_BODY" =~ "${VERSION_CHANGE_PREFIX}${VERSION_CHANGE_TYPES[2]}" ]]; then
    # major version
    PATCH="0"
    MINOR="0"
    MAJOR=$((MAJOR+1))
else
    # non-versioned
    echo -e "Detected non-versioned change, exiting"
    sleep 0.5
    exit 0
fi

if [[ "$MERGED" != "true" ]]; then
    echo -e "PR is not merged, exiting"
    sleep 0.5
    exit 0
fi

export TRAVIS_TAG="v$MAJOR.$MINOR.$PATCH"

# create tag
git tag $TRAVIS_TAG
git push --tags

export DO_GITHUB_RELEASE="true"

