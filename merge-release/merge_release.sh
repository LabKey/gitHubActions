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

echo "Merge approved PR from ${MERGE_BRANCH} to ${TARGET_BRANCH}."
if echo "$MERGE_BRANCH" | grep "fb_[0-9]*\.[0-9]*-SNAPSHOT"; then
	if hub api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/merge"  --raw-field "merge_method=squash"; then
		echo "Merge successful!"
		exit 0
	fi
else
	git fetch --unshallow
	git checkout "$TARGET_BRANCH"
	if git merge origin/"$MERGE_BRANCH" -m "Merge ${VERSION} to ${TARGET_BRANCH}" && git push; then
		echo "Merge successful!";
		exit 0
	fi
fi

echo "Failed to merge!" >&2
hub api "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" --raw-field "body=__ERROR__ Automatic merge failed!"
exit 1
