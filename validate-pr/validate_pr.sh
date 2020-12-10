#!/usr/bin/env bash

if ! command -v hub; then
  echo 'Error: GitHub command line tool is not installed.' >&2
fi

PR_NUMBER=$1
HEAD_BRANCH=$2 # fb_featureName
BASE_BRANCH=$3 # develop
PR_TITLE=$4
ERROR_FILE="errors.tmp"

if [ -z "$BASE_BRANCH" ] || [ -z "$HEAD_BRANCH" ] || [ -z "$PR_NUMBER" ] || [ -z "$PR_TITLE" ]; then
	echo "PR info not specified" >&2
	exit 1
fi

rm "$ERROR_FILE"

REL_PATTERN='^release([0-9]+\.[0-9]+)$'				# release20.11
SNAP_PATTERN='^release([0-9]+\.[0-9]+)-SNAPSHOT$'	# release20.11-SNAPSHOT
FF_PATTERN='^ff_([0-9]+\.[0-9]+).+'					# ff_20.11.0
FB_PATTERN='^fb_.+'									# fb_newFeature_12345
RFB_PATTERN='^([0-9]+\.[0-9]+)_fb_.+'				# 20.11_fb_backportFeature_12345


if [[ "$HEAD_BRANCH" =~ $FB_PATTERN ]]; then
	if [ "$BASE_BRANCH" != "develop" ]; then
		echo "Expect PR from \`${HEAD_BRANCH}\` to target \`develop\`, not \`${BASE_BRANCH}\`" >> "$ERROR_FILE"
		if [[ "$BASE_BRANCH" =~ $SNAP_PATTERN ]] || [[ "$BASE_BRANCH" =~ $REL_PATTERN ]]; then
			version=${BASH_REMATCH[1]}
			echo "If this branch is intended for ${version}, it should be named \`${version}_${HEAD_BRANCH}\`." >> "$ERROR_FILE"
			echo "_Note: A new PR will have to be created._" >> "$ERROR_FILE"
		fi
	fi
elif [[ "$HEAD_BRANCH" =~ $RFB_PATTERN ]]; then
	version=${BASH_REMATCH[1]}
	expected_branch="release${version}-SNAPSHOT"
	if [ "$BASE_BRANCH" != "$expected_branch" ]; then
		echo "Expect PR from \`${HEAD_BRANCH}\` to target \`${expected_branch}\`, not \`${BASE_BRANCH}\`" >> "$ERROR_FILE"
	fi
elif [[ "$HEAD_BRANCH" =~ $FF_PATTERN ]]; then
	version=${BASH_REMATCH[1]}
	expected_branch="release${version}"
	if [ "$BASE_BRANCH" != "$expected_branch" ]; then
		echo "Expect PR from \`${HEAD_BRANCH}\` to target \`${expected_branch}\`, not \`${BASE_BRANCH}\`" >> "$ERROR_FILE"
		echo "_Note: \`ff_*\` branches are reserved for our release process._" >> "$ERROR_FILE"
	fi
elif [[ "$BASE_BRANCH" =~ $SNAP_PATTERN ]] || [[ "$BASE_BRANCH" =~ $REL_PATTERN ]]; then
	version=${BASH_REMATCH[1]}
	echo "Branch doesn't match LabKey naming scheme." >> "$ERROR_FILE"
	echo "Branch intended for \`${version}\` should be named something like \`${version}_fb_${HEAD_BRANCH}\`" >> "$ERROR_FILE"
	echo "_Note: A new PR will have to be created_" >> "$ERROR_FILE"
elif [ "$BASE_BRANCH" == "develop" ]; then
	echo "Branch doesn't match LabKey naming scheme." >> "$ERROR_FILE"
	echo "Branch intended for \`develop\` should be named something like \`fb_${HEAD_BRANCH}\`" >> "$ERROR_FILE"
	echo "_Note: A new PR will have to be created_" >> "$ERROR_FILE"
fi

DEFAULT_TITLE="^Fb | fb "
if [[ "$PR_TITLE" =~ $DEFAULT_TITLE ]]; then
	if [ -f "$ERROR_FILE" ]; then
		echo "" >> "$ERROR_FILE" # Insert blank line after other errors.
	fi
    echo "This PR appears to be using the default title. Please use something more descriptive." >> "$ERROR_FILE"
fi


if [ -f "$ERROR_FILE" ]; then
	if [[ "$BASE_BRANCH" =~ $REL_PATTERN ]] && ! [[ "$HEAD_BRANCH" =~ $FF_PATTERN ]]; then
		echo "_Note: Pull requests should not target non-snapshot release branches directly._" >> "$ERROR_FILE"
	fi
	cat "$ERROR_FILE" >&2
	if [ "$PR_NUMBER" != "TEST" ]; then
		hub api "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" --field "body=@${ERROR_FILE}"
	fi
fi
