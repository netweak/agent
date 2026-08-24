#!/usr/bin/env bats

# Lifecycle tests for install.sh
# Must run inside Docker as root

TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
MOCK_API_PORT=8092

setup_file() {
	# Start mock server to serve agent files and handle API calls
	export MOCK_API_LOG="/tmp/mock_api_install.log"
	python3 "$TESTS_DIR/helpers/mock_api_server.py" "$MOCK_API_PORT" "$PROJECT_DIR" &
	echo $! > /tmp/mock_api_install_pid
	sleep 1
}

teardown_file() {
	if [ -f /tmp/mock_api_install_pid ]; then
		kill "$(cat /tmp/mock_api_install_pid)" 2>/dev/null || true
		rm -f /tmp/mock_api_install_pid
	fi
	rm -f /tmp/mock_api_install.log
}

setup() {
	load '../helpers/test_helper'

	# Clean up any previous installation
	if [ -d /etc/netweak ]; then
		crontab -u netweak -r 2>/dev/null || true
		rm -rf /etc/netweak
		userdel netweak 2>/dev/null || true
	fi
}

teardown() {
	# Clean up after each test
	if [ -d /etc/netweak ]; then
		crontab -u netweak -r 2>/dev/null || true
		rm -rf /etc/netweak
		userdel netweak 2>/dev/null || true
	fi
}

run_install() {
	local tmp_installer="/tmp/netweak_test_install.sh"
	cp "$PROJECT_DIR/install.sh" "$tmp_installer"
	DOWNLOAD_BASE="http://localhost:$MOCK_API_PORT/raw" \
		ENDPOINT="http://localhost:$MOCK_API_PORT" \
		bash "$tmp_installer" "$@"
}

@test "install: creates /etc/netweak directory" {
	run_install test-token-install 2>/dev/null
	[ -d /etc/netweak ]
}

@test "install: creates netweak user" {
	run_install test-token-install 2>/dev/null
	run id -u netweak
	assert_success
}

@test "install: sets up cron job" {
	run_install test-token-install 2>/dev/null
	run crontab -u netweak -l
	assert_success
	assert_output --partial "agent.sh"
}

@test "install: config has correct token" {
	run_install test-token-install 2>/dev/null
	run grep '^token=' /etc/netweak/config.conf
	assert_output "token=test-token-install"
}

@test "install: all required files present" {
	run_install test-token-install 2>/dev/null
	[ -f /etc/netweak/agent.sh ]
	[ -f /etc/netweak/lib.sh ]
	[ -f /etc/netweak/update.sh ]
	[ -f /etc/netweak/uninstall.sh ]
	[ -f /etc/netweak/config.conf ]
}

@test "install: --debug sets debug=1 in config" {
	run_install test-token-debug --debug 2>/dev/null
	run grep '^debug=' /etc/netweak/config.conf
	assert_output "debug=1"
}

# ENDPOINT is set here so the install talks to the mock rather than the real
# dev API; what --dev is being checked for is the separate install path.
@test "install: --dev installs alongside a production agent" {
	run_install test-token-dev --dev 2>/dev/null

	[ -d /etc/netweak-develop ]
	[ ! -d /etc/netweak ]

	run grep '^endpoint=' /etc/netweak-develop/config.conf
	assert_output "endpoint=http://localhost:$MOCK_API_PORT"

	crontab -u netweak-develop -r 2>/dev/null || true
	rm -rf /etc/netweak-develop
	userdel netweak-develop 2>/dev/null || true
}

@test "install: reinstall removes old files" {
	# First install
	run_install test-token-first 2>/dev/null

	# Create a marker file
	touch /etc/netweak/marker.txt

	# Re-install
	run_install test-token-second 2>/dev/null

	# Marker should be gone (old dir removed)
	[ ! -f /etc/netweak/marker.txt ]

	# New token should be present
	run grep '^token=' /etc/netweak/config.conf
	assert_output "token=test-token-second"
}

@test "install: fails without root" {
	# Create a non-root test user (nobody may be expired on some distros)
	useradd -r -s /bin/bash netweak-testuser 2>/dev/null || true
	run su -s /bin/bash netweak-testuser -c "bash $PROJECT_DIR/install.sh test-token 2>&1"
	assert_failure
	assert_output --partial "root"
	userdel netweak-testuser 2>/dev/null || true
}

@test "install: fails without token" {
	run bash "$PROJECT_DIR/install.sh" 2>&1
	assert_failure
}

@test "install: project token exchanges for server token" {
	run_install mock_project_token 2>/dev/null
	[ -d /etc/netweak ]
	run grep '^token=' /etc/netweak/config.conf
	assert_output "token=mock_server_token_abc123"
}

# What update.sh does: hand back the server token the machine already holds.
@test "install: an already-registered server token is reused" {
	run_install test-token-check 2>/dev/null
	[ -d /etc/netweak ]
	run grep '^token=' /etc/netweak/config.conf
	assert_output "token=test-token-check"
}

@test "install: invalid token fails before anything is installed" {
	run run_install invalid_token 2>&1
	assert_failure
	assert_output --partial "Invalid token"
	[ ! -d /etc/netweak ]
	run id -u netweak
	assert_failure
}

@test "install: plan limit reached fails with billing link" {
	run run_install mock_project_token_at_limit 2>&1
	assert_failure
	assert_output --partial "limit reached"
	[ ! -d /etc/netweak ]
}

@test "install: sends a first report instead of waiting for cron" {
	run_install mock_project_token 2>/dev/null
	run grep -c '"path": "/agent/report"' /tmp/mock_api_install.log
	assert_success
}
