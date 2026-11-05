#!/bin/sh
set -eu
bin="${1:-./build/sp0rkle}"
"$bin" --version | grep -q 'x86-64 Linux, NASM'
"$bin" --self-test | grep -q 'self-test: PASS'
set +e
"$bin" --not-a-real-option >/dev/null
status=$?
set -e
[ "$status" -eq 2 ]
echo "smoke tests: PASS"
