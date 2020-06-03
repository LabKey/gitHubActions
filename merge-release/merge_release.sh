#!/usr/bin/env bash

if command -v hub; then
  echo 'Error: GitHub command line tool is not installed.' >&2
  exit 1
fi

TRIAGE_ALIAS='LabKey/Releasers'

PR_NUMBER=$1
MERGE_BRANCH=$2 # ff_19.3.11
TARGET_BRANCH=$3 # release19.3
if [ -z $TARGET_BRANCH ] || [ -z $MERGE_BRANCH ] || [ -z $PR_NUMBER ]; then
	echo "PR info not specified" >&2
	exit 1
fi

git config --global user.name "github-actions"
git config --global user.email "teamcity@labkey.com"

echo "Merge approved PR from $MERGE_BRANCH to $TARGET_BRANCH."
git fetch --unshallow
git checkout $TARGET_BRANCH
if [ git merge origin/$MERGE_BRANCH -m "Merge $MERGE_BRANCH to $TARGET_BRANCH" && git push ]; then
	echo "Merge successful!";
else
	echo "Failed to merge!" >&2
	hub api repos/{owner}/{repo}/issues/$PR_NUMBER/comments --raw-field 'body=@'$TRIAGE_ALIAS' __ERROR__ Automatic merge failed!'
	exit 1
fi
