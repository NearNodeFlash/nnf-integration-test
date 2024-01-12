#!/bin/bash

function usage() {
    echo
    echo "Verify the md5sums of two files match"
    echo "This is used after copy_out directives to ensure the copy_in file matches the copy_out file"
    echo
    echo "Syntax: copy-out.sh FILE_IN FILE_OUT"
    echo
    echo "example:"
    echo "copy-out.sh /lus/global/testuser/test.in /lus/global/testuser/test.out"
    echo
}

COPY_IN=$1
COPY_OUT=$2

if [[ -z "$COPY_IN" ]]; then
    usage
    exit 1
elif [[ -z "$COPY_OUT" ]]; then
    usage
    exit 1
fi

if [ ! -e "$COPY_IN" ]; then
    echo "$COPY_IN does not exist"
    exit 1
fi

if [ ! -e "$COPY_OUT" ]; then
    echo "$COPY_OUT does not exist"
    exit 1
fi

COPY_IN_MD5SUM=$(md5sum "$COPY_IN" | awk '{print $1}')
COPY_OUT_MD5SUM=$(md5sum "$COPY_OUT" | awk '{print $1}')

echo "$COPY_IN: $COPY_IN_MD5SUM"
echo "$COPY_OUT: $COPY_OUT_MD5SUM"

if [ "$COPY_IN_MD5SUM" = "$COPY_OUT_MD5SUM" ]; then
    echo "md5sums match"
    exit 0
else
    echo "md5sums do not match"
    exit 1
fi
