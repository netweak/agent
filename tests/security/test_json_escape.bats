#!/usr/bin/env bats

# Security tests for JSON escaping — ensures json_str prevents injection

setup() {
	load '../helpers/test_helper'
	TEST_TMP="$(mktemp -d)"
}

teardown() {
	rm -rf "$TEST_TMP"
}

validate_json_value() {
	local escaped="$1"
	# Write a JSON document to a file and validate with Python
	printf '{"val": "%s"}' "$escaped" > "$TEST_TMP/test.json"
	python3 -m json.tool "$TEST_TMP/test.json" > /dev/null
}

@test "json_escape: quotes in input produce valid JSON" {
	local escaped
	escaped=$(json_str 'hostname with "quotes"')
	run validate_json_value "$escaped"
	assert_success
}

@test "json_escape: backslashes in input produce valid JSON" {
	local escaped
	escaped=$(json_str 'path\to\file')
	run validate_json_value "$escaped"
	assert_success
}

@test "json_escape: newlines in input produce valid JSON" {
	local escaped
	escaped=$(json_str $'line1\nline2\nline3')
	run validate_json_value "$escaped"
	assert_success
}

@test "json_escape: tabs in input produce valid JSON" {
	local escaped
	escaped=$(json_str $'col1\tcol2\tcol3')
	run validate_json_value "$escaped"
	assert_success
}

@test "json_escape: combined special chars produce valid JSON" {
	local escaped
	escaped=$(json_str $'say "hello"\there\n\\end')
	run validate_json_value "$escaped"
	assert_success
}

@test "json_escape: long process-list-style string produces valid JSON" {
	local escaped
	escaped=$(json_str 'root 2.5 1024 /usr/bin/bash;www-data 1.0 512 nginx: worker "process";admin 0.5 256 sshd: admin@pts/0')
	run validate_json_value "$escaped"
	assert_success
}
