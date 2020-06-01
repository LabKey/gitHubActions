#!/bin/bash

if ! [ -x "$(command -v hub)" ]; then
  echo 'Error: GitHub command line tool is not installed.' >&2
  exit 1
fi

TRIAGE_ALIAS='LabKey/Releasers'

if [ -z $GITHUB_SHA ]; then
	echo "Commit hash not specified" >&2
	exit 1
fi

if [ -z $GITHUB_REF ]; then
	echo "Tag not specified" >&2
	exit 1
fi

echo $GITHUB_REF | grep 'refs/heads' && {
	echo "Reference is not a tag: $GITHUB_REF" >&2
	exit 1
}

# Trim leading 'refs/tags/'
TAG=$(echo "$GITHUB_REF" | sed -e 's/refs\/tags\///')

# Trim patch number from tag '19.3.11' => '19.3'
RELEASE_NUM=$(echo "$TAG" | grep -oE '([0-9]+\.[0-9]+)')

if [ -z $RELEASE_NUM ]; then
	echo "Tag does not appear to be for a release: $TAG" >&2
	exit 1
fi

SNAPSHOT_BRANCH="release$RELEASE_NUM-SNAPSHOT"
RELEASE_BRANCH="release$RELEASE_NUM"

# Initial release branch creation (e.g. TAG=20.7.RC0)
echo "Create $SNAPSHOT_BRANCH branch."
hub api repos/{owner}/{repo}/git/refs --raw-field "ref=refs/heads/$SNAPSHOT_BRANCH" --raw-field "sha=$GITHUB_SHA"
SNAPSHOT_CREATED="$?"
echo ""

echo "Create $RELEASE_BRANCH branch."
hub api repos/{owner}/{repo}/git/refs --raw-field "ref=refs/heads/$RELEASE_BRANCH" --raw-field "sha=$GITHUB_SHA"
RELEASE_CREATED="$?"
echo ""

if [ $SNAPSHOT_CREATED == 0 ] && [ $RELEASE_CREATED == 0 ]; then
	echo "$RELEASE_NUM branches successfully created."
	exit 0
fi

# Create branch and PR for final release
git fetch --unshallow
RELEASE_DIFF=$(git log --cherry-pick --oneline --no-decorate origin/$RELEASE_BRANCH..$GITHUB_SHA | grep -v -e '^$')
echo ""
if [ $? != 0 ]; then
	echo "No changes to merge for $TAG."
	exit 0
else
	echo "Create fast-forward branch for $TAG."
	FF_BRANCH="ff_$TAG"
	hub api repos/{owner}/{repo}/git/refs --raw-field "ref=refs/heads/$FF_BRANCH" --raw-field "sha=$GITHUB_SHA"
	if [ $? != 0 ]; then
		echo "Failed to create branch: $FF_BRANCH" >&2
		exit 1
	fi
	echo "Create pull request."
	hub pull-request -f -h $FF_BRANCH -b $RELEASE_BRANCH -a $TRIAGE_ALIAS -r $TRIAGE_ALIAS \
		-m "Fast-forward for $TAG" \
		-m "_Generated automatically._" \
		-m "**Approve all matching PRs simultaneously.**" \
		-m "**Approval will trigger automatic merge.**"
	if [ $? != 0 ]; then
		echo "Failed to create pull request for $FF_BRANCH" >&2
		exit 1
	fi
fi

# Determine next non-monthly release
MERGE_MAP=( "19.2:19.3"
		    "19.3:20.3"
  			"20.3:20.7"
   			"20.7:20.11"
    		"20.11:21.3"
     		"21.3:21.7"
      		"21.7:21.11"
       		"21.11:22.3"
     		"22.3:22.7"
      		"22.7:22.11"
       		"22.11:23.3" )
for step in "${MERGE_MAP[@]}" ; do
    KEY=${step%%:*}
    VALUE=${step#*:}
    if [ $KEY == $RELEASE_NUM ]; then
		TARGET_BRANCH=release$VALUE-SNAPSHOT
    	hub api repos/{owner}/{repo}/git/refs/heads/$TARGET_BRANCH && {
			MERGE_BRANCH=$VALUE'_fb_merge_'$TAG
			NEXT_RELEASE=$VALUE
    	}
		echo ""
    	break
    fi
done
if [ -z $MERGE_BRANCH ]; then
	TARGET_BRANCH='develop'
	NEXT_RELEASE='develop'
	MERGE_BRANCH=fb_merge_$TAG
fi

git config --global user.name "github-actions[bot]"
git config --global user.email "teamcity@labkey.com"

# Create branch and PR for merge forward
git checkout -b $MERGE_BRANCH --no-track origin/$TARGET_BRANCH
git merge --no-ff $GITHUB_SHA -m "Merge $TAG to $NEXT_RELEASE" && {
	git push -u origin $MERGE_BRANCH
	if [ $? != 0 ]; then
		echo "Failed to push merge branch: $MERGE_BRANCH" >&2
		exit 1
	fi
	hub pull-request -f -h $MERGE_BRANCH -b $TARGET_BRANCH -a $TRIAGE_ALIAS -r $TRIAGE_ALIAS \
		-m "Merge $TAG to $NEXT_RELEASE" \
		-m "_Generated automatically._" \
		-m "**Approve all matching PRs simultaneously.**" \
		-m "**Approval will trigger automatic merge.**"
	if [ $? != 0 ]; then
		echo "Failed to create pull request for $MERGE_BRANCH" >&2
		exit 1
	fi
} || {
	# merge failed
	git merge --abort
	if [ $? != 0 ]; then
		# If the --abort fails, a conflict didn't cause the merge to fail
		echo "Unable to merge merge $TAG to $NEXT_RELEASE" >&2
		exit 1
	fi
	git reset --hard $GITHUB_SHA
	git push -u origin $MERGE_BRANCH
	if [ $? != 0 ]; then
		echo "Failed to push merge branch: $MERGE_BRANCH" >&2
		exit 1
	fi
	hub pull-request -f -h $MERGE_BRANCH -b $TARGET_BRANCH -a $TRIAGE_ALIAS -r $TRIAGE_ALIAS \
		-m "Merge $TAG to $NEXT_RELEASE (Conflicts)" \
		-m "_Automatic merge failed!_ Please merge '$TARGET_BRANCH' into '$MERGE_BRANCH' and resolve conflicts manually." \
		-m "**Approve all matching PRs simultaneously.**" \
		-m "**Approval will trigger automatic merge.**"
	if [ $? != 0 ]; then
		echo "Failed to create pull request for $MERGE_BRANCH" >&2
		exit 1
	fi
}
