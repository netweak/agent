#!/bin/bash

# Shared BATS test helper
# Sources lib.sh functions and loads assertion libraries

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"

# Load BATS support libraries
load "$TESTS_DIR/bats-support/load"
load "$TESTS_DIR/bats-assert/load"

# Source the shared function library
source "$PROJECT_DIR/lib.sh"
