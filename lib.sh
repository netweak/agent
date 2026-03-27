#!/bin/bash

# Netweak Agent — shared pure functions
# Sourced by agent.sh at runtime and by tests directly.

# Trim whitespace and return first line
prep() {
	echo "$1" | sed 's/^ *//; s/ *$//; q'
}

# Integer values (truncate decimal)
int() {
	echo "${1%%.*}"
}

# Filter numeric (returns 0 for non-numeric input)
num() {
	case "$1" in
		'' | *[!0-9.]*) echo 0 ;;
		*) echo "$1" ;;
	esac
}

# Escape string for JSON
json_str() {
	local str="$1"
	str="${str//\\/\\\\}"
	str="${str//\"/\\\"}"
	str="${str//$'\t'/\\t}"
	str="${str//$'\n'/\\n}"
	str="${str//$'\r'/\\r}"
	printf '%s' "$str"
}
