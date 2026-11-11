#!/usr/bin/env bash

# bash strict mode (modified) -- http://redsymbol.net/articles/unofficial-bash-strict-mode/
set -uo pipefail
IFS=$'\n\t'

if ! command -v hub; then
  echo 'Error: GitHub command line tool is not installed.' >&2
  exit 1
fi

PR_NUMBER=$1
MERGE_BRANCH=$2 # ff_19.3.11
TARGET_BRANCH=$3 # release19.3
if [ -z "${TARGET_BRANCH:-}" ] || [ -z "${MERGE_BRANCH:-}" ] || [ -z "${PR_NUMBER:-}" ]; then
	echo "PR info not specified" >&2
	exit 1
fi

# Extract version from branch name (e.g. "20.11.3" from "21.1_fb_merge_20.11.3")
VERSION="$( echo "$MERGE_BRANCH" | grep -oE '([^_]+)$' )"

git config --global user.name "github-actions"
git config --global user.email "teamcity@labkey.com"

# GitHub doesn't always delete the head branch after a PR is merged. Delete it explicitly so that stale branches don't
# interfere with subsequent releases. Failure is not fatal; the merge has already succeeded.
function delete_merge_branch() {
	local merged=false
	local response

	# Wait for GitHub to mark the PR as merged. Deleting the head branch first would close the PR without merging it.
	for _ in {1..12}; do
		# Capture response before searching it; piping directly to 'grep -q' can fail with SIGPIPE under pipefail
		response="$(hub api "repos/{owner}/{repo}/pulls/${PR_NUMBER}")"
		if grep -qE '"merged":[[:space:]]*true' <<< "$response"; then
			merged=true
			break
		fi
		sleep 5
	done
	if ! $merged; then
		echo "::warning::PR #${PR_NUMBER} has not been marked as merged. Not deleting ${MERGE_BRANCH}." >&2
		return
	fi

	echo "Delete merged branch: ${MERGE_BRANCH}"
	if ! response="$(hub api -XDELETE "repos/{owner}/{repo}/git/refs/heads/${MERGE_BRANCH}" 2>&1)"; then
		if grep -q 'Reference does not exist' <<< "$response"; then
			# GitHub deleted it automatically
			echo "${MERGE_BRANCH} has already been deleted."
		else
			echo "::warning::Failed to delete merged branch: ${MERGE_BRANCH}" >&2
			echo "$response" >&2
		fi
	fi
}

echo "Merge approved PR from ${MERGE_BRANCH} to ${TARGET_BRANCH}."
if echo "$MERGE_BRANCH" | grep "fb_[0-9]*\.[0-9]*-SNAPSHOT"; then
	# Special branch name for updating SNAPSHOT	version in develop (e.g. 'fb_21.12-SNAPSHOT')
	echo "Triggering squash merge of ${MERGE_BRANCH} to update SNAPSHOT version"
	if hub api -XPUT "repos/{owner}/{repo}/pulls/${PR_NUMBER}/merge" --raw-field "merge_method=squash"; then
		echo "Merge successful!"
		exit 0
	fi
else
	git fetch --unshallow
	git checkout "$TARGET_BRANCH"
	if git merge origin/"$MERGE_BRANCH" -m "Merge ${VERSION} to ${TARGET_BRANCH} (#${PR_NUMBER})" && git push; then
		echo "Merge successful!";
		delete_merge_branch
		exit 0
	fi
fi

echo "Failed to merge!" >&2
hub api "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" --raw-field "body=__ERROR__ Automatic merge failed!"
exit 1
