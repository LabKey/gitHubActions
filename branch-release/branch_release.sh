#!/usr/bin/env bash

if ! command -v hub; then
  echo 'Error: GitHub command line tool is not installed.' >&2
  exit 1
fi

REVIEWER1='labkey-tchad'
REVIEWER2='labkey-klum'
ASSIGNEE='labkey-teamcity'

if [ -z "$GITHUB_SHA" ]; then
	echo "Commit hash not specified" >&2
	exit 1
fi

if [ -z "$GITHUB_REF" ]; then
	echo "Tag not specified" >&2
	exit 1
fi

if ! echo "$GITHUB_REF" | grep 'refs/tags'; then
	echo "Reference is not a tag: ${GITHUB_REF}" >&2
	exit 1
fi

# Trim leading 'refs/tags/'
TAG="$( echo "$GITHUB_REF" | sed -e 's/refs\/tags\///' )"

# Trim patch number from tag '19.3.11' => '19.3'
RELEASE_NUM="$( echo "$TAG" | grep -oE '([0-9]+\.[0-9]+)' )"

if [ -z "$RELEASE_NUM" ]; then
	echo "Tag does not appear to be for a release: ${TAG}" >&2
	exit 1
fi

# RexExes for extracting branch information from GitHub compare API response
# $> hub api repos/{owner}/{repo}/compare/develop...${GITHUB_SHA}) | grep -oE ${AHEAD_BY_EXP} | cut -d':' -f 2
AHEAD_BY_EXP='"ahead_by":\d+'
BEHIND_BY_EXP='"behind_by":\d+'

# Get patch number from tag '19.3.11' => '11'
PATCH_NUMBER="$( echo "$TAG" | cut -d'.' -f3- )"

SNAPSHOT_BRANCH="release${RELEASE_NUM}-SNAPSHOT"
RELEASE_BRANCH="release${RELEASE_NUM}"

# Just create release branches if they don't exist
if ! hub api "repos/{owner}/{repo}/branches/${SNAPSHOT_BRANCH}"; then
	# Check to see if TeamCity tagged the wrong branch
	AHEAD_DEVELOP="$(hub api repos/{owner}/{repo}/compare/develop...${GITHUB_SHA} | grep -oE ${AHEAD_BY_EXP} | cut -d':' -f 2)"
	echo ""
	if [ -z "$AHEAD_DEVELOP" ]; then
		echo "Unable to compare ${TAG} to develop." >&2
		exit 1
	fi
	if [ $AHEAD_DEVELOP > 0 ]; then
		echo "${TAG} is ${AHEAD_DEVELOP} commits ahead of develop; refusing to create release branches." >&2
		exit 1
	fi

	# Initial release branch creation (e.g. TAG=20.7.RC0)
	echo "Create ${SNAPSHOT_BRANCH} branch."
	hub api 'repos/{owner}/{repo}/git/refs' --raw-field "ref=refs/heads/${SNAPSHOT_BRANCH}" --raw-field "sha=${GITHUB_SHA}"
	SNAPSHOT_CREATED="$?"
	echo ""

	echo "Create ${RELEASE_BRANCH} branch."
	hub api 'repos/{owner}/{repo}/git/refs' --raw-field "ref=refs/heads/${RELEASE_BRANCH}" --raw-field "sha=${GITHUB_SHA}"
	RELEASE_CREATED="$?"
	echo ""

	if [ $SNAPSHOT_CREATED == 0 ] && [ $RELEASE_CREATED == 0 ]; then
		echo "${RELEASE_NUM} branches successfully created."
		exit 0
	else
		echo "Failed to create ${RELEASE_NUM} release branches." >&2
		exit 1
	fi
fi

# Tag should be at or ahead of release branch
BEHIND_RELEASE="$(hub api repos/{owner}/{repo}/compare/${RELEASE_BRANCH}...${GITHUB_SHA} | grep -oE ${BEHIND_BY_EXP} | cut -d':' -f 2)"
echo ""
if [ $BEHIND_RELEASE > 0 ]; then
	echo "Improper release tag. ${TAG} is ${BEHIND_RELEASE} commit(s) behind latest release." >&2
	exit 1
fi
# Tag should not be ahead of SNAPSHOT branch
AHEAD_SNAPSHOT="$(hub api repos/{owner}/{repo}/compare/${SNAPSHOT_BRANCH}..${GITHUB_SHA} | grep -oE ${AHEAD_BY_EXP} | cut -d':' -f 2)"
echo ""
if [ $AHEAD_SNAPSHOT > 0 ]; then
	echo "Improper release tag. ${TAG} is ${AHEAD_SNAPSHOT} commit(s) ahead of current snapshot branch." >&2
	exit 1
fi

# Create branch and PR for final release
if [ -z "$PATCH_NUMBER" ]; then
	echo "${TAG} is not a patch release, just triggering merging forward."
	echo "Delete temporary tag"
	git push origin :refs/tags/"$TAG"
elif [ -z "$RELEASE_DIFF" ]; then
	echo "No changes to merge for ${TAG}."
else
	echo "Create fast-forward branch for ${TAG}."
	FF_BRANCH="ff_${TAG}"
	if ! hub api 'repos/{owner}/{repo}/git/refs' --raw-field "ref=refs/heads/${FF_BRANCH}" --raw-field "sha=${GITHUB_SHA}"; then
		echo "Failed to create branch: ${FF_BRANCH}" >&2
		exit 1
	fi
	echo "Create pull request."
	if ! hub pull-request -f -h "$FF_BRANCH" -b "$RELEASE_BRANCH" -a "$ASSIGNEE" -r "$REVIEWER1" -r "$REVIEWER2" \
		-m "Fast-forward for ${TAG}" \
		-m "_Generated automatically._" \
		-m "**Approve all matching PRs simultaneously.**" \
		-m "**Approval will trigger automatic merge.**";
	then
		echo "Failed to create pull request for $FF_BRANCH" >&2
		exit 1
	fi
fi

# Determine next non-monthly release
release_major="$(echo "$RELEASE_NUM" | cut -d'.' -f1)"
release_minor="$(echo "$RELEASE_NUM" | cut -d'.' -f2)"

case "_${release_minor}" in
  _11) NEXT_RELEASE="$(( release_major + 1 )).3" ;;
  _3|_7) NEXT_RELEASE="${release_major}.$(( release_minor + 4 ))";;
esac

if [ -n "$NEXT_RELEASE" ]; then
	TARGET_BRANCH=release${NEXT_RELEASE}-SNAPSHOT
	if hub api "repos/{owner}/{repo}/git/refs/heads/${TARGET_BRANCH}"; then
		MERGE_BRANCH="${NEXT_RELEASE}_fb_merge_${TAG}"
	fi
	echo ""
fi

# Next release doesn't exist, merge to develop
if [ -z "$MERGE_BRANCH" ]; then
	TARGET_BRANCH='develop'
	NEXT_RELEASE='develop'
	MERGE_BRANCH=fb_merge_${TAG}
fi

AHEAD_DEVELOP="$(hub api repos/{owner}/{repo}/compare/develop...${GITHUB_SHA} | grep -oE ${AHEAD_BY_EXP} | cut -d':' -f 2)"
if [ $AHEAD_DEVELOP == 0 ]; then
	echo "${TAG} has already been merged forward."
	exit 0
fi

git config --global user.name "github-actions"
git config --global user.email "teamcity@labkey.com"

git fetch --unshallow

# Create branch and PR for merge forward
git checkout -b "$MERGE_BRANCH" --no-track origin/"$TARGET_BRANCH"
if git merge --no-ff "$GITHUB_SHA" -m "Merge ${TAG} to ${NEXT_RELEASE}"; then
	if ! git push -u origin "$MERGE_BRANCH"; then
		echo "Failed to push merge branch: ${MERGE_BRANCH}" >&2
		exit 1
	fi
	if ! hub pull-request -f -h "$MERGE_BRANCH" -b "$TARGET_BRANCH" -a "$ASSIGNEE" -r "$REVIEWER1" -r "$REVIEWER2" \
		-m "Merge ${TAG} to ${NEXT_RELEASE}" \
		-m "_Generated automatically._" \
		-m "**Approve all matching PRs simultaneously.**" \
		-m "**Approval will trigger automatic merge.**";
	then
		echo "Failed to create pull request for ${MERGE_BRANCH}" >&2
		exit 1
	fi
else
	# merge failed
	if ! git merge --abort; then
		# If the --abort fails, a conflict didn't cause the merge to fail
		echo "Unable to merge merge ${TAG} to ${NEXT_RELEASE}" >&2
		exit 1
	fi

	if ! git reset --hard "$GITHUB_SHA" || ! git push -u origin "$MERGE_BRANCH"; then
		echo "Failed to push merge branch: ${MERGE_BRANCH}" >&2
		exit 1
	fi

	if ! hub pull-request -f -h "$MERGE_BRANCH" -b "$TARGET_BRANCH" -a "$ASSIGNEE" -r "$REVIEWER1" -r "$REVIEWER2" \
		-m "Merge ${TAG} to ${NEXT_RELEASE} (Conflicts)" \
		-m "_Automatic merge failed!_ Please merge '${TARGET_BRANCH}' into '${MERGE_BRANCH}' and resolve conflicts manually." \
		-m "**Approve all matching PRs simultaneously.**" \
		-m "**Approval will trigger automatic merge.**";
	then
		echo "Failed to create pull request for ${MERGE_BRANCH}" >&2
		exit 1
	fi
fi
