#!/bin/bash

WRAPPER_NAME=${WRAPPER_NAME:-"ktools.sh"}
WRAPPER_DOCKER_IMAGE=${WRAPPER_DOCKER_IMAGE:-"premiereglobal/ktools:latest"}

CONTAINER_WRAPPER_VERSION=$(grep -m 1 KTOOLS_VERSION $WRAPPER_NAME | cut -d'=' -f2 | tr -d '\n')

# there are two commands currently
# wrapper - prints out the ktools script in this container
# wrapper-version - prints out the version of the ktools script in this container
if [ "$1" == "wrapper" ]; then
  cat "$WRAPPER_NAME"
  exit 0
elif [ "$1" == "wrapper-version" ]; then
  echo "$CONTAINER_WRAPPER_VERSION"
  exit 0
fi


# Sanity check the container run environment
#echo "version = $WRAPPER_VERSION"
#echo "expected = $CONTAINER_WRAPPER_VERSION"

# This is for future use for an auto update feature
if [[ "$AUTO_UPDATE" == "true" && "$WRAPPER_VERSION" != "$CONTAINER_WRAPPER_VERSION" ]]; then
  if [ ! -z "$SUPPRESS_OUT_OF_DATE_OUTPUT" ]; then
    exit 6
  fi
  if [ ! -z "$WRAPPER_VERSION" ]; then
    echo "Your $WRAPPER_NAME version ($WRAPPER_VERSION) is out of date. Please update it to $CONTAINER_WRAPPER_VERSION." >&2
    echo "" >&2
  fi
  echo "Run this command to update $WRAPPER_NAME:" >&2
  echo >&2
  echo "  docker run --rm $WRAPPER_DOCKER_IMAGE wrapper > $WRAPPER_NAME && chmod +x $WRAPPER_NAME" >&2
  echo >&2
  echo "...then, " >&2
  echo >&2
  echo "  ./$WRAPPER_NAME" >&2
  exit 6
fi