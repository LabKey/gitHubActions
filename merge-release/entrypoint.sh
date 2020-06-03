#!/usr/bin/env bash

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "GITHUB_TOKEN is not defined." >&2
  exit 1
fi

if [[ -z "$GITHUB_WORKSPACE" ]]; then
  echo "GITHUB_WORKSPACE is not available." >&2
  exit 1
fi

cd $GITHUB_WORKSPACE

bash -c "/merge_release.sh $*"