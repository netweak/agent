#!/usr/bin/env bats

setup() {
	load '../helpers/test_helper'
}

@test "num passes valid integer" {
	result=$(num "123")
	assert_equal "$result" "123"
}

@test "num passes valid decimal" {
	result=$(num "1.5")
	assert_equal "$result" "1.5"
}

@test "num rejects empty string" {
	result=$(num "")
	assert_equal "$result" "0"
}

@test "num rejects alphabetic input" {
	result=$(num "abc")
	assert_equal "$result" "0"
}

@test "num rejects mixed alphanumeric" {
	result=$(num "12abc")
	assert_equal "$result" "0"
}

@test "num rejects negative numbers" {
	result=$(num "-5")
	assert_equal "$result" "0"
}

@test "num passes zero" {
	result=$(num "0")
	assert_equal "$result" "0"
}
