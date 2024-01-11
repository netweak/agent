#!/bin/bash

# Set env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# API Token
if [ -f /etc/netweak/token.conf ]
then
	auth=($(cat /etc/netweak/token.conf))
else
	echo "Error: File /etc/netweak/token.conf is missing."
	exit 1
fi

# Build data for post
data_post="token=${auth[0]}"

# API request with automatic termination
if [ -n "$(command -v timeout)" ]
then
	timeout -s SIGKILL 30 wget -q -o /dev/null -O /etc/netweak/log/agent.log -T 25 --post-data "$data_post" --no-check-certificate "https://api.netweak.com/agent/heartbeat"
else
	wget -q -o /dev/null -O /etc/netweak/log/agent.log -T 25 --post-data "$data_post" --no-check-certificate "https://api.netweak.com/agent/heartbeat"
	wget_pid=$!
	wget_counter=0
	wget_timeout=30

	while kill -0 "$wget_pid" && (( wget_counter < wget_timeout ))
	do
	    sleep 1
	    (( wget_counter++ ))
	done

	kill -0 "$wget_pid" && kill -s SIGKILL "$wget_pid"
fi

# Finished
exit 1
