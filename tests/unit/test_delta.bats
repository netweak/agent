#!/usr/bin/env bats

# Tests for the delta calculation logic from agent.sh lines 238-260.
# Since the delta code is inline (not a function), we replicate the arithmetic
# in a helper and verify the math with known inputs.

setup() {
	load '../helpers/test_helper'
}

# Helper that replicates agent.sh delta calculation logic
calculate_deltas() {
	local time=$1 cpu=$2 io=$3 idle=$4 rx=$5 tx=$6
	local prev_time=$7 prev_cpu=$8 prev_io=$9 prev_idle=${10} prev_rx=${11} prev_tx=${12}

	local cpu_gap=$(( cpu - prev_cpu ))
	local io_gap=$(( io - prev_io ))
	local idle_gap=$(( idle - prev_idle ))
	local load_cpu=0 load_io=0 rx_gap=0 tx_gap=0

	if (( cpu_gap > 0 )); then
		load_cpu=$(( (1000 * (cpu_gap - idle_gap) / cpu_gap + 5) / 10 ))
	fi

	if (( io_gap > 0 )); then
		load_io=$(( (1000 * (io_gap - idle_gap) / io_gap + 5) / 10 ))
	fi

	if (( rx > prev_rx )); then
		rx_gap=$(( rx - prev_rx ))
	fi

	if (( tx > prev_tx )); then
		tx_gap=$(( tx - prev_tx ))
	fi

	echo "$load_cpu $load_io $rx_gap $tx_gap"
}

@test "delta: CPU load percentage with known values" {
	# cpu_gap = 63200 - 50000 = 13200
	# idle_gap = 55000 - 50000 = 5000
	# load_cpu = (1000 * (13200 - 5000) / 13200 + 5) / 10 = (1000 * 8200 / 13200 + 5) / 10
	# = (621 + 5) / 10 = 62
	result=$(calculate_deltas 1000 63200 55400 55000 2000 3000 \
	                          940  50000 50400 50000 1000 2000)
	read -ra vals <<< "$result"
	assert_equal "${vals[0]}" "62"
}

@test "delta: IO load percentage with known values" {
	# io_gap = 55400 - 50400 = 5000
	# idle_gap = 55000 - 50000 = 5000
	# load_io = (1000 * (5000 - 5000) / 5000 + 5) / 10 = (0 + 5) / 10 = 0
	result=$(calculate_deltas 1000 63200 55400 55000 2000 3000 \
	                          940  50000 50400 50000 1000 2000)
	read -ra vals <<< "$result"
	assert_equal "${vals[1]}" "0"
}

@test "delta: rx/tx gap when current > cached" {
	result=$(calculate_deltas 1000 63200 55400 55000 5000 8000 \
	                          940  50000 50400 50000 3000 6000)
	read -ra vals <<< "$result"
	assert_equal "${vals[2]}" "2000"
	assert_equal "${vals[3]}" "2000"
}

@test "delta: rx/tx gap is 0 when counter resets (current < cached)" {
	result=$(calculate_deltas 1000 63200 55400 55000 100 200 \
	                          940  50000 50400 50000 5000 8000)
	read -ra vals <<< "$result"
	assert_equal "${vals[2]}" "0"
	assert_equal "${vals[3]}" "0"
}

@test "delta: cpu_gap of 0 results in load_cpu 0" {
	# Same cpu values — gap is 0, division should be skipped
	result=$(calculate_deltas 1000 50000 50400 50000 2000 3000 \
	                          940  50000 50400 50000 1000 2000)
	read -ra vals <<< "$result"
	assert_equal "${vals[0]}" "0"
}
