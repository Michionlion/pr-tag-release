#!/bin/bash

# This script requires Travis CI's env vars
# and a GITHUB_OAUTH_TOKEN env var

### Variable Setup ###

DEPLOY_BRANCH=${DEPOY_BRANCH-"^master$"}
MERGE_COMMIT_REGEX=${MERGE_COMMIT_REGEX-"Merge pull request #([0-9]+)"}
PATCH_CHANGE_REGEX=${PATCH_CHANGE_REGEX-"This (PR|release) is an?( small| tiny)? (update|bugfix)"}
MINOR_CHANGE_REGEX=${MINOR_CHANGE_REGEX-"This (PR|release) is a (feature( update| change)?|big (update|change))"}
MAJOR_CHANGE_REGEX=${MAJOR_CHANGE_REGEX-"This (PR|release) (is a (compatibility[ -])?breaking (update|change)| breaks( backwards)? compatibility)"}
PRERELEASE_REGEX=${PRERELEASE_REGEX-"\[(PRE|WIP|PRERELEASE)\]"}
DRAFT_REGEX=${DRAFT_REGEX-"\[(WIP|DRAFT)\]"}

LATEST_COMMIT_MSG="$(git log -1 --pretty=%B)"
LATEST_VERSION=$(git describe --abbrev=0 --tags)
LATEST_VERSION="${LATEST_VERSION#"v"}"
IFS='.' read -ra VERSION_SPLIT <<<"$LATEST_VERSION"
MAJOR=${VERSION_SPLIT[0]-0}
MINOR=${VERSION_SPLIT[1]-0}
PATCH=${VERSION_SPLIT[2]-0}

GIT_EMAIL="travis@travis-ci.com"
GIT_USER="Travis CI"



### Functions ###

function escape_markdown() {
	escaped=$(printf '%s' "$1" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
	escaped="${escaped%\"}"
	escaped="${escaped#\"}"
	echo "$escaped"
}

function status() {
	echo -e "==> Current Semantic Version"
	echo -e "$MAJOR.$MINOR.$PATCH"
	echo -e "<=="
	echo -e "==> Commit Message"
	echo -e "$LATEST_COMMIT_MSG"
	echo -e "<=="
}

function export_pr_num() {
	# detect if merge commit (uses Github's default message from the web interface)
	if [[ "$LATEST_COMMIT_MSG" =~ $MERGE_COMMIT_REGEX ]]; then
		export PR_NUM="${BASH_REMATCH[1]}"
		echo -e "==> Detected merged pull request"
		echo -e "PR #$PR_NUM"
		echo -e "<=="
		return 0
	else
		echo -e "Could not detect PR number from commit message, exiting"
		return 1
	fi
}

function check_valid_state() {
	if [[ -n "$TRAVIS_TAG" ]]; then
		echo -e "Current commit ($TRAVIS_COMMIT) already has a tag"
		echo -e "Don't tag a PR merge commit manually, exiting"
		return 1
	elif [[ ! "$TRAVIS_BRANCH" =~ $DEPLOY_BRANCH ]]; then
		echo -e "Not on deploy branch, exiting"
		return 1
	fi
	return 0
}

# expects #1 to be a file name to write to
function get_pr_info() {
	if [[ -z "$GITHUB_OAUTH_TOKEN" ]]; then
		curl "https://api.github.com/repos/${TRAVIS_REPO_SLUG}/pulls/${PR_NUM}" | jq '[.title, .body, .merged]' > "$1"
	else
		curl -H "Authorization: token ${GITHUB_OAUTH_TOKEN}" "https://api.github.com/repos/${TRAVIS_REPO_SLUG}/pulls/${PR_NUM}" | jq '[.title, .body, .merged]' > "$1"
	fi

	if [[ -z "$(cat "$1")" ]]; then
		echo -e "PR request response empty"
		return 1
	fi
	if [[ "$(jq '.[2]' < "$1")" != "true" ]]; then
		echo -e "PR is not merged, exiting"
		return 1
	fi

	return 0
}

function export_pr_info() {
	local json="${TRAVIS_COMMIT}_pr_result.json"
	get_pr_info "$json" || return 1
	TITLE="$(jq '.[0]' < "$json")"
	PR_BODY="$(jq '.[1]' < "$json")"
	PR_BODY="${PR_BODY%\"}"
	PR_BODY="${PR_BODY#\"}"
	DRAFT="false"
	PRERELEASE="false"
	if [[ "$TITLE" =~ $PRERELEASE_REGEX ]]; then
		DRAFT="true"
	fi
	if [[ "$TITLE" =~ $DRAFT_REGEX ]]; then
		PRERELEASE="true"
	fi
	export DRAFT
	export PRERELEASE
	export TITLE
	export PR_BODY
	return 0
}

# must have access to $PR_BODY
function update_version() {
	local update
	if [[ "$PR_BODY" =~ $PATCH_CHANGE_REGEX ]]; then
		# patch version
		PATCH=$((PATCH+1))
		update="Patch"
	elif [[ "$PR_BODY" =~ $MINOR_CHANGE_REGEX ]]; then
		# minor version
		PATCH="0"
		MINOR=$((MINOR+1))
		update="Minor"
	elif [[ "$PR_BODY" =~ $MAJOR_CHANGE_REGEX ]]; then
		# major version
		PATCH="0"
		MINOR="0"
		MAJOR=$((MAJOR+1))
		update="Major"
	else
		# non-versioned
		unset TRAVIS_TAG
		echo -e "Detected unversioned change, exiting"
		return 1
	fi
	TRAVIS_TAG="$MAJOR.$MINOR.$PATCH"
	echo -e "==> Updated Semantic Version"
	echo -e "$update version update to $TRAVIS_TAG"
	echo -e "<=="
	export TRAVIS_TAG="v$TRAVIS_TAG"
	return 0
}

function create_release_body() {
	# Generate release body
	RELEASE_BODY="$(cat <<-EOF
		$(echo -e "${TITLE}")

		$(echo -e "${PR_BODY}")

		*Build auto-generated by [pr-tag-release](https://github.com/Michionlion/pr-tag-release)*
		EOF
	)"

	echo -e "==> Release Description"
	echo -e "$RELEASE_BODY"
	echo -e "<=="


	# shellcheck disable=SC2155
	export RELEASE_BODY=$(escape_markdown "$RELEASE_BODY")
}

function set_up_git() {
	git config --global user.email "$GIT_EMAIL"
	git config --global user.name "$GIT_USER"

	# set remote url to use GITHUB_OAUTH_TOKEN
	# assumes github.com, normal url, etc.
	export REMOTE_URL="https://${GITHUB_OAUTH_TOKEN}@github.com/${TRAVIS_REPO_SLUG}.git"
}

function create_version_tag() {
	# create tag
	git tag -a $TRAVIS_TAG -m "$TITLE"
	if ! git push "$REMOTE_URL" --tags 1>/dev/null 2>&1; then
		echo -e "Failed to push tags!"
		return 1
	fi
	echo -e "==> Created Tag"
	echo -e "$(git tag -n25 "$TRAVIS_TAG")"
	echo -e "<=="
	return 0
}

function post_release() {
	# shellcheck disable=SC2155
	local data="$(cat <<-EOF
		{
			"tag_name": "${TRAVIS_TAG}",
			"target_commitish": "${TRAVIS_BRANCH}",
			"name": "${TRAVIS_TAG}",
			"body": "${RELEASE_BODY}",
			"draft": ${DRAFT},
			"prerelease": ${PRERELEASE}
		}
		EOF
	)"

	echo -e "==> POST Request Body"
	echo "$data"
	echo -e "<=="

	CODE=$(curl -i -s -o /dev/null -w "%{http_code}" \
		-X "POST" -H "Content-Type: application/json" \
		-H "Authorization: token ${GITHUB_OAUTH_TOKEN}" -d "$data" \
		"https://api.github.com/repos/${TRAVIS_REPO_SLUG}/releases")

	echo -e "==> POST Request Response"
	echo "$CODE"
	echo -e "<=="

	if [[ ! "$CODE" -eq "201" ]]; then
		echo -e "Failed to create release!"
		return 1
	fi
	return 0
}


### MAIN ###

status

export_pr_num || return 0
check_valid_state || return 0
export_pr_info || return 0
update_version || return 0

create_release_body

set_up_git
create_version_tag || return 0
post_release || return 0

export DO_GITHUB_RELEASE="true"

return 0
