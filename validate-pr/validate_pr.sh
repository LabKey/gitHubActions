#!/usr/bin/env bash

if ! command -v hub; then
  echo 'Error: GitHub command line tool is not installed.' >&2
  exit 1
fi

PR_NUMBER=$1
HEAD_BRANCH=$2 # fb_featureName
BASE_BRANCH=$3 # develop
PR_TITLE=$4

if [ -z "$BASE_BRANCH" ] || [ -z "$HEAD_BRANCH" ] || [ -z "$PR_NUMBER" ] || [ -z "$PR_TITLE" ]; then
	echo "PR info not specified" >&2
	exit 1
fi


if ! echo "$BASE_BRANCH" | grep -E '^release[0-9]+\.[0-9]+$'; then
	echo "Reference is not a tag: ${GITHUB_REF}" >&2
	exit 1
fi



echo "Merge approved PR from ${HEAD_BRANCH} to ${BASE_BRANCH}."
git fetch --unshallow
git checkout "$BASE_BRANCH"
if git merge origin/"$HEAD_BRANCH" -m "Merge ${HEAD_BRANCH} to ${BASE_BRANCH}" && git push; then
	echo "Merge successful!";
else
	echo "Failed to merge!" >&2
	hub api "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" --raw-field "body=__ERROR__ Automatic merge failed!"
	exit 1
fi
