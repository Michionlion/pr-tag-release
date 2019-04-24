#!/bin/bash

# This script requires Travis CI's env vars
# and a GITHUB_OAUTH_TOKEN env var

### Variable Setup ###

MERGE_COMMIT_REGEX=${MERGE_COMMIT_REGEX-"Merge pull request #([0-9]+)"}
PATCH_CHANGE_REGEX=${PATCH_CHANGE_REGEX-"This (PR|release) is an?( small| tiny)? (update|bugfix|change)"}
MINOR_CHANGE_REGEX=${MINOR_CHANGE_REGEX-"This (PR|release) is a (feature( update| change)?|big (update|change))"}
MAJOR_CHANGE_REGEX=${MAJOR_CHANGE_REGEX-"This (PR|release) (is a ((compatibility[ -])?breaking|major) (update|change)| breaks( backwards)? compatibility)"}
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

export PATCH_LABEL_COLOR="14a3bc"
export PATCH_LABEL_NAME="patch"
export PATCH_LABEL_DESC="This PR updates the patch version: v0.0.X"

export MINOR_LABEL_COLOR="23e059"
export MINOR_LABEL_NAME="minor"
export MINOR_LABEL_DESC="This PR updates the minor version: v0.X.0"

export MAJOR_LABEL_COLOR="c60f7a"
export MAJOR_LABEL_NAME="major"
export MAJOR_LABEL_DESC="This PR updates the major version: vX.0.0"


function does_label_exist() {
	OUTPUT=$(curl -X "GET" -s --write-out "PR_TAG_CODE=%{http_code}" \
		-H "Content-Type: application/json" \
		-H "Accept: application/vnd.github.symmetra-preview+json" \
		-H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
		"https://api.github.com/repos/${TRAVIS_REPO_SLUG}/labels/$1")

	CODE=${OUTPUT##*PR_TAG_CODE=}

	#shellcheck disable=SC2046
	return $(test "$CODE" = "200")
}

function create_labels() {
	for label_type in "MAJOR" "MINOR" "PATCH"; do
		local color; local name; local desc
		color="${label_type}_LABEL_COLOR"
		color=${!color}
		name="${label_type}_LABEL_NAME"
		name=${!name}
		name="${label_type}_LABEL_NAME"
		name=${!name}
		desc="${label_type}_LABEL_DESC"
		desc=${!desc}

		if does_label_exist "$name"; then
			# label exists -- patch it/do nothing
			echo -e "$name label already exists, doing nothing"
		else
			# shellcheck disable=SC2155
			local data="$(cat <<-EOF
				{"name": "$name",
				"description": "$desc",
				"color": "$color"}
				EOF
			)"
			
			OUTPUT=$(curl -X "POST" -s --write-out "PR_TAG_CODE=%{http_code}" \
				-H "Content-Type: application/json" \
				-H "Accept: application/vnd.github.symmetra-preview+json" \
				-H "Authorization: token ${GITHUB_OAUTH_TOKEN}" -d "$data" \
				"https://api.github.com/repos/${TRAVIS_REPO_SLUG}/labels")
			CODE=${OUTPUT##*PR_TAG_CODE=}
			OUTPUT=${OUTPUT%PR_TAG_CODE=*}
			if [[ "$CODE" != "201" ]]; then
				echo -e "Failed to create version labels!"
				return 1
			fi
			echo -e "created $label label"
		fi
	done
}

function set_label_on() {
	local issue="$1"
	local label="$2"

	# get all labels on issue
	OUTPUT=$(curl -X "GET" -s --write-out "PR_TAG_CODE=%{http_code}" \
		-H "Content-Type: application/json" \
		-H "Accept: application/vnd.github.symmetra-preview+json" \
		-H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
		"https://api.github.com/repos/${TRAVIS_REPO_SLUG}/issues/${issue}/labels")
	CODE=${OUTPUT##*PR_TAG_CODE=}
	OUTPUT=${OUTPUT%PR_TAG_CODE=*}
	if [[ "$CODE" != "200" ]]; then
		echo -e "Failed to retrieve current labels on issue $issue!"
		return 1
	fi
	
	local labels_to_delete; local has_label
	IFS=$'\n' read -ra labels_to_delete <<<"$(echo "$OUTPUT" | jq --raw-output ".[].name | select(test(\"$MAJOR_LABEL_NAME|$MINOR_LABEL_NAME|$PATCH_LABEL_NAME\")) | select(. != \"$label\")")"
	has_label=$(echo "$OUTPUT" | jq "[.[].name] | any(. == \"$label\")")

	if [[ ${#labels_to_delete[@]} -ne 0 ]]; then
		# delete the labels
		for to_delete in "${labels_to_delete[@]}"; do
			OUTPUT=$(curl -X "DELETE" -s --write-out "PR_TAG_CODE=%{http_code}" \
				-H "Content-Type: application/json" \
				-H "Accept: application/vnd.github.symmetra-preview+json" \
				-H "Authorization: token ${GITHUB_OAUTH_TOKEN}" \
				"https://api.github.com/repos/${TRAVIS_REPO_SLUG}/issues/${issue}/labels/$to_delete")
			CODE=${OUTPUT##*PR_TAG_CODE=}
			OUTPUT=${OUTPUT%PR_TAG_CODE=*}
			if [[ "$CODE" != "200" ]]; then
				echo -e "Failed to delete label $to_delete on issue $issue!"
				return 1
			fi
		done
	fi

	if [[ "$has_label" = "false" ]]; then
		# shellcheck disable=SC2155
		local data="{\"labels\": [\"$label\"]}"
		OUTPUT=$(curl -X "POST" -s --write-out "PR_TAG_CODE=%{http_code}" \
			-H "Content-Type: application/json" \
			-H "Accept: application/vnd.github.symmetra-preview+json" \
			-H "Authorization: token ${GITHUB_OAUTH_TOKEN}" -d "$data" \
			"https://api.github.com/repos/${TRAVIS_REPO_SLUG}/issues/${issue}/labels")
		CODE=${OUTPUT##*PR_TAG_CODE=}
		OUTPUT=${OUTPUT%PR_TAG_CODE=*}
		if [[ "$CODE" != "200" ]]; then
			echo -e "Failed to add label $label on issue $issue!"
			return 1
		fi
		echo -e "set version label to $label"
	else
		echo -e "current label is already correct, doing nothing"
	fi
}

function update_label() {
	echo -e "==> Create Labels"
	create_labels || return 1
	local label;
	label="${UPDATE_TYPE^^}_LABEL_NAME"
	echo -e "==> Set Label"
	set_label_on "$PR_NUM" "$label" || return 1
	return 0
}

function is_pr() {
	# shellcheck disable=SC2046
	return $(test "$TRAVIS_PULL_REQUEST" != "false")
}

function escape_markdown() {
	escaped=$(printf '%s' "$1" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
	escaped="${escaped%\"}"
	escaped="${escaped#\"}"
	echo "$escaped"
}

function status() {
	echo -e "==> Current Semantic Version"
	echo -e "$MAJOR.$MINOR.$PATCH"
	echo -e "==> Commit Message"
	echo -e "$LATEST_COMMIT_MSG"
}

function export_pr_num() {
	# detect if merge commit (uses Github's default message from the web interface)
	if [[ "$LATEST_COMMIT_MSG" =~ $MERGE_COMMIT_REGEX ]]; then
		export PR_NUM="${BASH_REMATCH[1]}"
		echo -e "==> Detected merged pull request"
		echo -e "PR #$PR_NUM"
		return 0
	elif is_pr; then
		export PR_NUM=$TRAVIS_PULL_REQUEST
		echo -e "==> Detected open pull request"
		return 0
	else
		echo -e "Could not detect PR number from commit message or PR build, exiting"
		return 1
	fi
}

function check_valid_state() {
	if [[ -n "$TRAVIS_TAG" ]]; then
		echo -e "Current commit ($TRAVIS_COMMIT) already has a tag"
		echo -e "Don't tag a PR merge commit manually, exiting"
		return 1
	fi
	return 0
}

# expects $1 to be a file name to write to
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

	return 0
}

function export_pr_info() {
	local json="${TRAVIS_COMMIT}_pr_result.json"
	get_pr_info "$json" || return 1
	TITLE="$(jq '.[0]' < "$json")"
	PR_BODY="$(jq '.[1]' < "$json")"
	MERGED="$(jq '.[2]' < "$json")"
	
	# trim quotes
	PR_BODY="${PR_BODY%\"}"
	PR_BODY="${PR_BODY#\"}"
	TITLE="${TITLE%\"}"
	TITLE="${TITLE#\"}"

	# detect draft/pre
	DRAFT="false"
	PRERELEASE="false"
	if [[ "$TITLE" =~ $PRERELEASE_REGEX ]]; then
		PRERELEASE="true"
	fi
	if [[ "$TITLE" =~ $DRAFT_REGEX ]]; then
		DRAFT="true"
	fi

	# export results
	export DRAFT
	export PRERELEASE
	export TITLE
	export PR_BODY
	export MERGED

	return 0
}

# must have access to $PR_BODY
function update_version() {
	if [[ "$PR_BODY" =~ $PATCH_CHANGE_REGEX ]]; then
		# patch version
		PATCH=$((PATCH+1))
		UPDATE_TYPE="Patch"
	elif [[ "$PR_BODY" =~ $MINOR_CHANGE_REGEX ]]; then
		# minor version
		PATCH="0"
		MINOR=$((MINOR+1))
		UPDATE_TYPE="Minor"
	elif [[ "$PR_BODY" =~ $MAJOR_CHANGE_REGEX ]]; then
		# major version
		PATCH="0"
		MINOR="0"
		MAJOR=$((MAJOR+1))
		UPDATE_TYPE="Major"
	else
		# non-versioned
		unset TRAVIS_TAG
		echo -e "Detected unversioned change, exiting"
		return 1
	fi
	TRAVIS_TAG="$MAJOR.$MINOR.$PATCH"
	echo -e "==> Updated Semantic Version"
	echo -e "$update version update to $TRAVIS_TAG"
	export TRAVIS_TAG="v$TRAVIS_TAG"
	export UPDATE_TYPE
	return 0
}

function create_release_body() {
	# Generate release body
	RELEASE_BODY="$(cat <<-EOF
		#### $(echo -e "${TITLE}")

		$(echo -e "${PR_BODY}")

		*Auto-generated by [pr-tag-release](https://github.com/Michionlion/pr-tag-release)*
		EOF
	)"

	echo -e "==> Release Description"
	echo -e "$RELEASE_BODY"


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
	return 0
}

function post_release() {
	# shellcheck disable=SC2155
	local data="$(cat <<-EOF
		{
			"tag_name": "${TRAVIS_TAG}",
			"target_commitish": "${TRAVIS_COMMIT}",
			"name": "${TRAVIS_TAG}",
			"body": "${RELEASE_BODY}",
			"draft": ${DRAFT},
			"prerelease": ${PRERELEASE}
		}
		EOF
	)"

	echo -e "==> POST Request Body"
	echo "$data"

	CODE=$(curl -i -s -o /dev/null -w "%{http_code}" \
		-X "POST" -H "Content-Type: application/json" \
		-H "Authorization: token ${GITHUB_OAUTH_TOKEN}" -d "$data" \
		"https://api.github.com/repos/${TRAVIS_REPO_SLUG}/releases")

	echo -e "==> POST Request Response"
	echo "$CODE"

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
create_release_body || return 0
update_version || return 0
update_label || return 0

# If not merged, exit
if test "$MERGED" != "true"; then
	unset TRAVIS_TAG
	echo -e "PR is not merged yet, exiting"
	return 0
fi

set_up_git
create_version_tag || return 0
post_release || return 0

export DO_GITHUB_RELEASE="true"

return 0
