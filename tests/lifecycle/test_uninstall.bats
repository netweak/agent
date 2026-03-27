#!/usr/bin/env bats

# Lifecycle tests for uninstall.sh
# Must run inside Docker as root

TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
MOCK_API_PORT=8093

setup_file() {
	export MOCK_API_LOG="/tmp/mock_api_uninstall.log"
	python3 "$TESTS_DIR/helpers/mock_api_server.py" "$MOCK_API_PORT" "$PROJECT_DIR" &
	echo $! > /tmp/mock_api_uninstall_pid
	sleep 1
}

teardown_file() {
	if [ -f /tmp/mock_api_uninstall_pid ]; then
		kill "$(cat /tmp/mock_api_uninstall_pid)" 2>/dev/null || true
		rm -f /tmp/mock_api_uninstall_pid
	fi
	rm -f /tmp/mock_api_uninstall.log
}

setup() {
	load '../helpers/test_helper'
}

teardown() {
	# Clean up in case test failed
	if [ -d /etc/netweak ]; then
		crontab -u netweak -r 2>/dev/null || true
		rm -rf /etc/netweak
		userdel netweak 2>/dev/null || true
	fi
}

install_agent() {
	DOWNLOAD_BASE="http://localhost:$MOCK_API_PORT/raw" \
		bash "$PROJECT_DIR/install.sh" test-token-uninstall 2>/dev/null
}

@test "uninstall: removes /etc/netweak directory" {
	install_agent
	bash /etc/netweak/uninstall.sh 2>/dev/null
	[ ! -d /etc/netweak ]
}

@test "uninstall: removes netweak user" {
	install_agent
	bash /etc/netweak/uninstall.sh 2>/dev/null
	run id -u netweak 2>&1
	assert_failure
}

@test "uninstall: removes cron job" {
	install_agent
	bash /etc/netweak/uninstall.sh 2>/dev/null
	run crontab -u netweak -l 2>&1
	assert_failure
}

@test "uninstall: fails without root" {
	install_agent
	run su -s /bin/bash nobody -c "bash /etc/netweak/uninstall.sh 2>&1"
	assert_failure
	assert_output --partial "root"
}

@test "uninstall: fails if not installed" {
	# Make sure it's not installed
	rm -rf /etc/netweak 2>/dev/null || true
	userdel netweak 2>/dev/null || true

	run bash "$PROJECT_DIR/uninstall.sh" 2>&1
	assert_failure
	assert_output --partial "not installed"
}
