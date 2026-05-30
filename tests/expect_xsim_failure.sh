#!/bin/bash
# Wrapper script that runs an xsim test and expects it to FAIL
# Usage: expect_xsim_failure.sh <path_to_xsim_test_executable>

XSIM_TEST="$1"

if [[ -z "$XSIM_TEST" ]]; then
    echo "Usage: $0 <xsim_test_executable>"
    exit 1
fi

# Run the xsim test
"$XSIM_TEST"
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "FAIL: Expected xsim test to fail, but it passed"
    exit 1
else
    echo "PASS: xsim test failed as expected (exit code: $EXIT_CODE)"
    exit 0
fi
