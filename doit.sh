#!/bin/bash

set -e

for i in {1..100}; do
	echo "Attempt start: $i"
	ginkgo -p --label-filter='simple' .
	echo "Attempt end: $i"
done
