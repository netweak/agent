#!/bin/bash

# Set env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Get the directory name
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="$(basename "$SCRIPT_DIR")"

echo -e "|\n|   Netweak Uninstaller\n|   ===================\n|"

# Check if user is root
if [ "$(id -u)" != "0" ]; then
	echo -e "|   Error: You need to be root to uninstall the Netweak agent\n|"
	exit 1
fi

# Check if agent is installed
if [ ! -d "/etc/$INSTALL_PATH" ]; then
	echo -e "|   Error: Netweak agent is not installed\n|"
	exit 1
fi

# Remove cron jobs
if id -u "$INSTALL_PATH" >/dev/null 2>&1; then
	echo -e "|   Removing cron jobs"
	crontab -u "$INSTALL_PATH" -r 2>/dev/null
fi

# Copy this script to tmp so we can delete the install dir
cp "$0" /tmp/netweak-uninstall-cleanup.sh

# Remove agent directory
echo -e "|   Removing /etc/$INSTALL_PATH"
rm -rf "/etc/${INSTALL_PATH:?}"

# Remove user
if id -u "$INSTALL_PATH" >/dev/null 2>&1; then
	echo -e "|   Removing user '$INSTALL_PATH'"
	userdel "$INSTALL_PATH"
fi

# Show success
echo -e "|\n|   Success: The Netweak agent has been uninstalled\n|"

# Clean up temp copy
rm -f /tmp/netweak-uninstall-cleanup.sh
