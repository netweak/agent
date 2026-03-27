#!/usr/bin/env bats

# Tests for JSON payload structure and validity
# Requires: Linux with mock /proc, mock API server, wget, python3

TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PROJECT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
FIXTURES_DIR="$TESTS_DIR/fixtures"
MOCK_API_LOG="/tmp/mock_api_payload_requests.log"
MOCK_API_PORT=8090

setup_file() {
	export MOCK_API_LOG
	python3 "$TESTS_DIR/helpers/mock_api_server.py" "$MOCK_API_PORT" &
	MOCK_API_PID=$!
	echo "$MOCK_API_PID" > /tmp/mock_api_payload_pid
	sleep 1

	# Run agent once and capture payload
	TEST_INSTALL_DIR="$(mktemp -d)"
	mkdir -p "$TEST_INSTALL_DIR/log"
	cp "$PROJECT_DIR/agent.sh" "$TEST_INSTALL_DIR/"
	cp "$PROJECT_DIR/lib.sh" "$TEST_INSTALL_DIR/"
	cat > "$TEST_INSTALL_DIR/config.conf" <<-EOF
		token=test-token-abc123
		version=1.3
		endpoint=http://localhost:$MOCK_API_PORT
		debug=0
	EOF

	cd "$TEST_INSTALL_DIR"
	PROC_DIR="$FIXTURES_DIR/proc" bash "$TEST_INSTALL_DIR/agent.sh" 2>/dev/null || true

	# Extract the report payload (second line in log)
	REPORT_BODY=$(sed -n '2p' "$MOCK_API_LOG" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['body'])")
	echo "$REPORT_BODY" > /tmp/test_report_payload.json

	rm -rf "$TEST_INSTALL_DIR"
}

teardown_file() {
	if [ -f /tmp/mock_api_payload_pid ]; then
		kill "$(cat /tmp/mock_api_payload_pid)" 2>/dev/null || true
		rm -f /tmp/mock_api_payload_pid
	fi
	rm -f "$MOCK_API_LOG" /tmp/test_report_payload.json
}

setup() {
	load '../helpers/test_helper'
}

@test "payload: report is valid JSON" {
	run python3 -m json.tool /tmp/test_report_payload.json
	assert_success
}

@test "payload: contains all required fields" {
	local required_fields=(
		token timestamp version uptime sessions processes
		processes_array file_handles file_handles_limit
		os_kernel os_name os_arch cpu_name cpu_cores cpu_freq
		ram_total ram_usage swap_total swap_usage
		disk_array disk_total disk_usage connections
		nic ipv4 ipv6 rx tx rx_gap tx_gap
		load load_cpu load_io ping_eu ping_us ping_as
	)

	local payload
	payload=$(cat /tmp/test_report_payload.json)

	for field in "${required_fields[@]}"; do
		run python3 -c "import json; d=json.loads('''$payload'''); assert '$field' in d, f'Missing: $field'"
		assert_success
	done
}

@test "payload: token matches config" {
	run python3 -c "
import json
with open('/tmp/test_report_payload.json') as f:
    d = json.load(f)
print(d['token'])
"
	assert_output "test-token-abc123"
}

@test "payload: version matches config" {
	run python3 -c "
import json
with open('/tmp/test_report_payload.json') as f:
    d = json.load(f)
print(d['version'])
"
	assert_output "1.3"
}

@test "payload: numeric fields are numbers not strings" {
	run python3 -c "
import json
with open('/tmp/test_report_payload.json') as f:
    d = json.load(f)
numeric_fields = ['uptime', 'sessions', 'processes', 'file_handles',
                   'file_handles_limit', 'cpu_cores', 'ram_total', 'ram_usage',
                   'swap_total', 'swap_usage', 'disk_total', 'disk_usage',
                   'connections', 'rx', 'tx', 'rx_gap', 'tx_gap',
                   'load_cpu', 'load_io']
for f in numeric_fields:
    assert isinstance(d[f], (int, float)), f'{f} should be numeric, got {type(d[f])}'
print('ok')
"
	assert_output "ok"
}
