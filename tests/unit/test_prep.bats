#!/usr/bin/env bats

setup() {
	load '../helpers/test_helper'
}

@test "prep strips leading whitespace" {
	result=$(prep "  hello")
	assert_equal "$result" "hello"
}

@test "prep strips trailing whitespace" {
	result=$(prep "hello  ")
	assert_equal "$result" "hello"
}

@test "prep strips both leading and trailing whitespace" {
	result=$(prep "  hello world  ")
	assert_equal "$result" "hello world"
}

@test "prep returns first line only" {
	result=$(prep $'line1\nline2\nline3')
	assert_equal "$result" "line1"
}

@test "prep handles empty string" {
	result=$(prep "")
	assert_equal "$result" ""
}

@test "prep passes clean strings unchanged" {
	result=$(prep "hello world")
	assert_equal "$result" "hello world"
}
