#!/bin/bash

LATEST_COMMIT_MSG="$(git log -1 --pretty=%B)"
LATEST_VERSION="$(git describe --abbrev=0 --tags)"
echo "READ: $LATEST_VERSION"
LATEST_VERSION="$(expr "$LATEST_VERSION" : "v\(\d+\.\d+\.\d+\)")"
echo "FIXED: $LATEST_VERSION"
VERSION_SPLIT=(${LATEST_VERSION//./ })

echo "ARRAY: $VERSION_SPLIT"

#get number parts and increase last one by 1
MAJOR=${VERSION_BITS[0]}
MINOR=${VERSION_BITS[1]}
PATCH=${VERSION_BITS[2]}

echo "FINAL: $MAJOR $MINOR $PATCH"

printf "MSG: %s" $LATEST_COMMIT_MSG



