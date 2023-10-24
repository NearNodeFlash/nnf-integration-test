#!/bin/bash

set -e

function usage() {
    echo
    echo "Create a file and/or directory at the rootpath with the given UID/GID."
    echo "This is used prior to copy_in directives to ensure the FILEPATH/directory are in"
    echo "place."
    echo
    echo "Syntax: copy-in.sh ROOT_DIR FILEPATH UID GID"
    echo
    echo "arguments:"
    echo "ROOT_DIR      root path directory; assume this is the global lustre"
    echo "              mount root (e.g. /lus/global)"
    echo "FILEPATH      filepath to the FILEPATH to create. This should be a"
    echo "              path (e.g. /testuser/test.in, test.in)"
    echo "UID           user ID of the filepath"
    echo "GID           groupd ID of the filepath"
    echo
    echo "examples:"
    echo "copy-in.sh /lus/global test.in 1050 1051"
    echo "copy-in.sh /lus/global testuser/test.in 1050 1051"
    echo
}

ROOT_DIR=$1
FILEPATH=$2
MYUID=$3
MYGID=$4

if [[ -z "$ROOT_DIR" ]]; then
    usage
    exit 1
elif [[ -z "$FILEPATH" ]]; then
    usage
    exit 1
elif [[ -z "$MYUID" ]]; then
    usage
    exit 1
elif [[ -z "$MYGID" ]]; then
    usage
    exit 1
fi

# Get the base diectory on top of global lustre and create the directory
BASEDIR=$(dirname $FILEPATH)
mkdir -p "$ROOT_DIR"/"$BASEDIR"

# Use the perl binary as our test FILEPATH
cp /usr/bin/perl "$ROOT_DIR"/"$FILEPATH"

# Set the permissions of the base dir
if [ "$BASEDIR" != "." ]; then
    chown -R "$MYUID":"$MYGID" "$ROOT_DIR"/"$BASEDIR"
# Otherwise just set the file directly if no base dir
else
    chown "$MYUID":"$MYGID" "$ROOT_DIR"/"$FILEPATH"
fi

# List the basedir contents
ls -alhR "$ROOT_DIR"/"$BASEDIR" #&>"$ROOT_DIR"/"$MYUSER"/test.output

set +e

exit 0
