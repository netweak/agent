#!/bin/bash

# Set env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Get the directory name
NETWEAK=$(basename $(dirname $0))

# API Token
if [ -f "/etc/$NETWEAK/token.conf" ]; then
	auth=($(cat "/etc/$NETWEAK/token.conf"))
else
	echo "Error: File /etc/$NETWEAK/token.conf is missing."
	exit 1
fi

# Get endpoint
if [ -f "/etc/$NETWEAK/endpoint.conf" ]; then
	ENDPOINT=$(cat "/etc/$NETWEAK/endpoint.conf")
else
	ENDPOINT="https://api.netweak.com"
fi

# Build data for post
data_post="token=${auth[0]}"

# API request with automatic termination
if [ -n "$(command -v timeout)" ]; then
	timeout -s SIGKILL 30 wget -q -o /dev/null -O "/etc/$NETWEAK/log/agent.log" -T 25 --post-data "$data_post" --no-check-certificate "$ENDPOINT/agent/heartbeat"
else
	wget -q -o /dev/null -O "/etc/$NETWEAK/log/agent.log" -T 25 --post-data "$data_post" --no-check-certificate "$ENDPOINT/agent/heartbeat"
	wget_pid=$!
	wget_counter=0
	wget_timeout=30

	while kill -0 "$wget_pid" && ((wget_counter < wget_timeout)); do
		sleep 1
		((wget_counter++))
	done

	kill -0 "$wget_pid" && kill -s SIGKILL "$wget_pid"
fi

# Finished
exit 1
