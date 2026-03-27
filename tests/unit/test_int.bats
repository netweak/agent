#!/usr/bin/env bats

setup() {
	load '../helpers/test_helper'
}

@test "int truncates decimal" {
	result=$(int "3.14")
	assert_equal "$result" "3"
}

@test "int passes integer through" {
	result=$(int "42")
	assert_equal "$result" "42"
}

@test "int handles zero point value" {
	result=$(int "0.99")
	assert_equal "$result" "0"
}

@test "int handles large number" {
	result=$(int "123456.789")
	assert_equal "$result" "123456"
}
