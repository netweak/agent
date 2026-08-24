#!/bin/bash
# shellcheck disable=SC1090,SC2154

# Set env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Get the directory name
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="$(basename "$SCRIPT_DIR")"

echo -e "|\n|   Netweak Updater\n|   ===================\n|"

# Check if user is root
if [ "$(id -u)" != "0" ]; then
	echo -e "|   Error: You need to be root to update the Netweak agent\n|"
	exit 1
fi

# Check if agent is installed
if [ ! -f "/etc/$INSTALL_PATH/config.conf" ]; then
	echo -e "|   Error: Netweak agent config not found\n|"
	exit 1
fi

# Read config
source "/etc/$INSTALL_PATH/config.conf"

# Build extra flags from config. An array, so an empty list passes no argument
# at all — quoting a string here sent " --debug" through as one positional and
# the installer never saw the flag.
EXTRA_FLAGS=()
if [ "${debug:-0}" -eq 1 ]; then
	EXTRA_FLAGS+=(--debug)
fi

# Determine if this is a dev install
if [ "$INSTALL_PATH" = "netweak-develop" ] || [ "$endpoint" = "https://api.netweak.dev" ]; then
	echo -e "|   Detected dev installation, updating from netweak.sh/dev\n|"
	curl -fsSL netweak.sh/dev | sudo bash -s "$token" --dev "${EXTRA_FLAGS[@]}"
else
	echo -e "|   Detected production installation, updating from netweak.sh\n|"
	curl -fsSL netweak.sh | sudo bash -s "$token" "${EXTRA_FLAGS[@]}"
fi
