#!/usr/bin/env bats

# Integration tests for agent.sh
# Requires: Linux with mock /proc, mock API server, wget

TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
FIXTURES_DIR="$TESTS_DIR/fixtures"
MOCK_API_LOG="/tmp/mock_api_requests.log"
MOCK_API_PORT=8089

setup_file() {
	# Start mock API server
	export MOCK_API_LOG
	python3 "$TESTS_DIR/helpers/mock_api_server.py" "$MOCK_API_PORT" &
	MOCK_API_PID=$!
	echo "$MOCK_API_PID" > /tmp/mock_api_pid
	sleep 1
}

teardown_file() {
	# Stop mock API server
	if [ -f /tmp/mock_api_pid ]; then
		kill "$(cat /tmp/mock_api_pid)" 2>/dev/null || true
		rm -f /tmp/mock_api_pid
	fi
	rm -f "$MOCK_API_LOG"
}

setup() {
	load '../helpers/test_helper'

	# Create a temporary install directory to simulate /etc/netweak
	TEST_INSTALL_DIR="$(mktemp -d)"
	mkdir -p "$TEST_INSTALL_DIR/log"

	# Copy agent and lib
	cp "$PROJECT_DIR/agent.sh" "$TEST_INSTALL_DIR/"
	cp "$PROJECT_DIR/lib.sh" "$TEST_INSTALL_DIR/"

	# Write test config
	cat > "$TEST_INSTALL_DIR/config.conf" <<-EOF
		token=test-token-abc123
		version=1.3
		endpoint=http://localhost:$MOCK_API_PORT
		debug=0
	EOF

	# Clear request log
	> "$MOCK_API_LOG"
}

teardown() {
	rm -rf "$TEST_INSTALL_DIR"
}

@test "agent sends heartbeat request" {
	cd "$TEST_INSTALL_DIR"

	PROC_DIR="$FIXTURES_DIR/proc" \
		bash "$TEST_INSTALL_DIR/agent.sh" 2>/dev/null || true

	# Check that heartbeat was sent
	run grep '/agent/heartbeat' "$MOCK_API_LOG"
	assert_success
}

@test "agent sends report request" {
	cd "$TEST_INSTALL_DIR"

	PROC_DIR="$FIXTURES_DIR/proc" \
		bash "$TEST_INSTALL_DIR/agent.sh" 2>/dev/null || true

	# Check that report was sent
	run grep '/agent/report' "$MOCK_API_LOG"
	assert_success
}

@test "agent sends exactly 2 POST requests" {
	cd "$TEST_INSTALL_DIR"

	PROC_DIR="$FIXTURES_DIR/proc" \
		bash "$TEST_INSTALL_DIR/agent.sh" 2>/dev/null || true

	run wc -l < "$MOCK_API_LOG"
	assert_output "2"
}

@test "agent calculates correct RAM usage from fixture" {
	cd "$TEST_INSTALL_DIR"

	PROC_DIR="$FIXTURES_DIR/proc" \
		bash "$TEST_INSTALL_DIR/agent.sh" 2>/dev/null || true

	# Expected: (8048056 - 2024000 - 3012000 - 512000) * 1024 = 2560057344
	run grep -o '"ram_usage": [0-9]*' "$MOCK_API_LOG"
	assert_output --partial '"ram_usage": 2560057344'
}

@test "agent extracts correct uptime from fixture" {
	cd "$TEST_INSTALL_DIR"

	PROC_DIR="$FIXTURES_DIR/proc" \
		bash "$TEST_INSTALL_DIR/agent.sh" 2>/dev/null || true

	# uptime fixture is 12345.67, int() truncates to 12345
	run grep -o '"uptime": [0-9]*' "$MOCK_API_LOG"
	assert_output --partial '"uptime": 12345'
}

@test "agent extracts correct file handles from fixture" {
	cd "$TEST_INSTALL_DIR"

	PROC_DIR="$FIXTURES_DIR/proc" \
		bash "$TEST_INSTALL_DIR/agent.sh" 2>/dev/null || true

	run grep -o '"file_handles": [0-9]*' "$MOCK_API_LOG"
	assert_output --partial '"file_handles": 1234'

	run grep -o '"file_handles_limit": [0-9]*' "$MOCK_API_LOG"
	assert_output --partial '"file_handles_limit": 65536'
}

@test "agent exits with error when config is missing" {
	rm -f "$TEST_INSTALL_DIR/config.conf"

	cd "$TEST_INSTALL_DIR"
	run bash "$TEST_INSTALL_DIR/agent.sh" 2>&1
	assert_failure
	assert_output --partial "missing"
}
