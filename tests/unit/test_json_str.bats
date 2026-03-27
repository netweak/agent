#!/usr/bin/env bats

setup() {
	load '../helpers/test_helper'
}

@test "json_str escapes backslashes" {
	result=$(json_str 'a\b')
	assert_equal "$result" 'a\\b'
}

@test "json_str escapes double quotes" {
	result=$(json_str 'say "hi"')
	assert_equal "$result" 'say \"hi\"'
}

@test "json_str escapes tabs" {
	result=$(json_str $'a\tb')
	assert_equal "$result" 'a\tb'
}

@test "json_str escapes newlines" {
	result=$(json_str $'a\nb')
	assert_equal "$result" 'a\nb'
}

@test "json_str escapes carriage returns" {
	result=$(json_str $'a\rb')
	assert_equal "$result" 'a\rb'
}

@test "json_str handles combined special characters" {
	result=$(json_str $'say "hello"\tworld\n\\end')
	assert_equal "$result" 'say \"hello\"\tworld\n\\end'
}

@test "json_str handles empty string" {
	result=$(json_str "")
	assert_equal "$result" ""
}
