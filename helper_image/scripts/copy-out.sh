#!/bin/bash

set -e

function usage() {
    echo
    echo "Verify the md5sums of two files match"
    echo "This is used after copy_out directives to ensure the copy_in file matches the copy_out file"
    echo
    echo "Syntax: copy-out.sh FILE_IN FILE_OUT <NUM_COMPUTES>"
    echo
    echo "Set <NUM_COMPUTES> to 0 when index mount directories are not expected. When expected, the "
    echo "path should include an asterik to represent the directories it needs to be escaped (\*)"
    echo
    echo "example:"
    echo "copy-out.sh /lus/global/testuser/test.in /lus/global/testuser/test.out 0"
    echo "copy-out.sh /lus/global/testuser/test.in /lus/global/testuser/\*/test.out 4"
    echo
}

COPY_IN=$1
COPY_OUT=$2
NUM_COMPUTES=$3

if [[ -z ${COPY_IN} ]]; then
    usage
    exit 1
elif [[ -z ${COPY_OUT} ]]; then
    usage
    exit 1
elif [[ -z ${NUM_COMPUTES} ]]; then
    usage
    exit 1
fi

if [[ ! -e ${COPY_IN} ]]; then
    echo "${COPY_IN} does not exist"
    exit 1
fi

if [[ ${NUM_COMPUTES} -gt 0 ]]; then
    echo "Checking for index mount directories"

    # remove any escaping or quotes from the path
    COPY_OUT=${COPY_OUT//\'/}
    COPY_OUT=${COPY_OUT//\\/}

    # verify there are $NUM_COMPUTES directories/files
    LS_OUTPUT=$(/bin/ls -l ${COPY_OUT})
    if ! echo "${LS_OUTPUT}" | wc -l | grep "${NUM_COMPUTES}"; then
        echo "missing index directories, expected ${NUM_COMPUTES}:"
        /bin/ls -l "${COPY_OUT}"
        exit 1
    fi

    COPY_IN_MD5SUM=$(md5sum "${COPY_IN}" | awk '{print $1}')
    echo "${COPY_IN}: ${COPY_IN_MD5SUM}"

    # make sure each checksum is the same
    md5sum ${COPY_OUT} | while read -r line; do
        SUM=$(echo "${line}" | awk '{print $1}')
        FILE=$(echo "${line}" | awk '{print $2}')
        echo "${FILE}: ${SUM}"

        if [[ ! ${COPY_IN_MD5SUM} = "${SUM}" ]]; then
            echo "md5sums do not match"
            exit 1
        fi
    done
else
    echo "Not checking for index mount directories"
    if [[ ! -e ${COPY_OUT} ]]; then
        echo "${COPY_OUT} does not exist"
        exit 1
    fi

    COPY_IN_MD5SUM=$(md5sum "${COPY_IN}" | awk '{print $1}')
    COPY_OUT_MD5SUM=$(md5sum "${COPY_OUT}" | awk '{print $1}')

    echo "${COPY_IN}: ${COPY_IN_MD5SUM}"
    echo "${COPY_OUT}: ${COPY_OUT_MD5SUM}"

    if [[ ${COPY_IN_MD5SUM} = "${COPY_OUT_MD5SUM}" ]]; then
        echo "md5sums match"
        exit 0
    else
        echo "md5sums do not match"
        exit 1
    fi
fi
