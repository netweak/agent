#!/usr/bin/env bats

# Security tests for file permissions after installation
# Must run inside Docker as root (after install.sh has been executed)

TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
MOCK_API_PORT=8091

setup_file() {
	# Start mock file server to serve agent files for install
	export MOCK_API_LOG="/tmp/mock_api_permissions.log"
	python3 "$TESTS_DIR/helpers/mock_api_server.py" "$MOCK_API_PORT" "$PROJECT_DIR" &
	echo $! > /tmp/mock_api_permissions_pid
	sleep 1

	# Run installer with mock download base (copy to temp to avoid self-delete)
	local tmp_installer="/tmp/netweak_test_install.sh"
	cp "$PROJECT_DIR/install.sh" "$tmp_installer"
	DOWNLOAD_BASE="http://localhost:$MOCK_API_PORT/raw" \
		ENDPOINT="http://localhost:$MOCK_API_PORT" \
		bash "$tmp_installer" test-token-permissions 2>/dev/null || true
}

teardown_file() {
	# Clean up
	bash /etc/netweak/uninstall.sh 2>/dev/null || true
	if [ -f /tmp/mock_api_permissions_pid ]; then
		kill "$(cat /tmp/mock_api_permissions_pid)" 2>/dev/null || true
		rm -f /tmp/mock_api_permissions_pid
	fi
	rm -f /tmp/mock_api_permissions.log
}

setup() {
	load '../helpers/test_helper'
}

@test "permissions: /etc/netweak owned by netweak user" {
	run stat -c '%U' /etc/netweak
	assert_output "netweak"
}

@test "permissions: /etc/netweak owned by netweak group" {
	run stat -c '%G' /etc/netweak
	assert_output "netweak"
}

@test "permissions: /etc/netweak has mode 700" {
	run stat -c '%a' /etc/netweak
	assert_output "700"
}

@test "permissions: config.conf not world-readable" {
	local perms
	perms=$(stat -c '%a' /etc/netweak/config.conf)
	# Last digit should be 0 (no other permissions)
	[[ "${perms: -1}" == "0" ]]
}

@test "permissions: agent.sh not world-writable" {
	local perms
	perms=$(stat -c '%a' /etc/netweak/agent.sh)
	# Last digit should not include write (2)
	local other="${perms: -1}"
	(( (other & 2) == 0 ))
}
