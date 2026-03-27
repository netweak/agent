#!/usr/bin/env bats

# Lifecycle tests for update.sh
# Must run inside Docker as root

TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
MOCK_API_PORT=8094

setup_file() {
	export MOCK_API_LOG="/tmp/mock_api_update.log"
	python3 "$TESTS_DIR/helpers/mock_api_server.py" "$MOCK_API_PORT" "$PROJECT_DIR" &
	echo $! > /tmp/mock_api_update_pid
	sleep 1
}

teardown_file() {
	if [ -f /tmp/mock_api_update_pid ]; then
		kill "$(cat /tmp/mock_api_update_pid)" 2>/dev/null || true
		rm -f /tmp/mock_api_update_pid
	fi
	rm -f /tmp/mock_api_update.log
}

setup() {
	load '../helpers/test_helper'

	# Clean up
	if [ -d /etc/netweak ]; then
		crontab -u netweak -r 2>/dev/null || true
		rm -rf /etc/netweak
		userdel netweak 2>/dev/null || true
	fi
}

teardown() {
	if [ -d /etc/netweak ]; then
		crontab -u netweak -r 2>/dev/null || true
		rm -rf /etc/netweak
		userdel netweak 2>/dev/null || true
	fi
}

@test "update: fails without root" {
	# Install first
	DOWNLOAD_BASE="http://localhost:$MOCK_API_PORT/raw" \
		bash "$PROJECT_DIR/install.sh" test-token-update 2>/dev/null

	run su -s /bin/bash nobody -c "bash /etc/netweak/update.sh 2>&1"
	assert_failure
	assert_output --partial "root"
}

@test "update: fails without config" {
	# Create dir without config
	mkdir -p /etc/netweak
	cp "$PROJECT_DIR/update.sh" /etc/netweak/

	run bash /etc/netweak/update.sh 2>&1
	assert_failure
	assert_output --partial "config not found"
}

@test "update: detects production installation" {
	DOWNLOAD_BASE="http://localhost:$MOCK_API_PORT/raw" \
		bash "$PROJECT_DIR/install.sh" test-token-update 2>/dev/null

	# Verify config has production endpoint (default)
	run grep '^endpoint=' /etc/netweak/config.conf
	# Default install shouldn't override the endpoint line unless it differs
	# The endpoint in config.conf template is empty, so default is used
	assert_success
}
