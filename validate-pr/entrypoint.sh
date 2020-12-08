#!/usr/bin/env bash

if [ -z "$GITHUB_TOKEN" ]; then
  echo "GITHUB_TOKEN is not defined." >&2
  exit 1
fi

bash -c "/validate_pr.sh $*"
