#!/bin/bash

LATEST_COMMIT_MSG="$(git log -1 --pretty=%B)"

printf "MSG: %s" $LATEST_COMMIT_MSG



