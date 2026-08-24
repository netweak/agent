#!/bin/bash

# Set env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Default values
VERSION="1.3"
BRANCH="main"
INSTALL_PATH="netweak"
DEBUG=0

# An explicit ENDPOINT wins over the one --dev would pick, so a test run can
# point the whole install at a local API. Resolved after argument parsing.
ENDPOINT_OVERRIDE="${ENDPOINT:-}"
DEFAULT_ENDPOINT="https://api.netweak.com"

# Function to display usage information
usage() {
	echo -e "| Usage: bash $0 [options] <token>\n|"
	echo -e "| Options:"
	echo -e "|       --dev               Use staging environment"
	echo -e "|       --debug             Enable debug mode\n|"
	exit 1
}

# Parse command line arguments
if ! PARSED_ARGS=$(getopt -o '' --long dev,debug -n "$0" -- "$@"); then
	usage
fi

eval set -- "$PARSED_ARGS"

# Parse arguments
while true; do
	case "$1" in
	--dev)
		DEFAULT_ENDPOINT="https://api.netweak.dev"
		BRANCH="develop"
		INSTALL_PATH="netweak-develop"
		shift
		;;
	--debug)
		DEBUG=1
		shift
		;;
	--)
		shift
		break
		;;
	*)
		echo "Internal error!"
		exit 1
		;;
	esac
done

ENDPOINT="${ENDPOINT_OVERRIDE:-$DEFAULT_ENDPOINT}"

# Get token
TOKEN="$1"

# Prepare output
echo -e "|\n|   Netweak Installer\n|   ===================\n|"

# Check if user is root
if [ "$(id -u)" != "0" ]; then
	echo -e "|   Error: You need to be root to install the Netweak agent\n|"
	echo -e "|          The agent itself will NOT be running as root but instead under its own non-privileged user\n|"
	exit 1
fi

# Required parameter
if [ -z "$TOKEN" ]; then
	usage
fi

# Check for curl
if ! command -v curl >/dev/null 2>&1; then
	echo -e "|\n|   Error: curl is required but not installed\n|"
	exit 1
fi

fail() {
	echo -e "|\n|   Error: $1\n|"
	exit 1
}

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

# Pull one string field out of the last response. The agent ships with no
# dependencies beyond curl, so there is no jq to lean on; this tolerates the
# whitespace a formatter might add, but not escaped quotes inside the value —
# tokens and API messages have neither.
json_field() {
	grep -o "\"$1\":[[:space:]]*\"[^\"]*\"" "$RESPONSE_FILE" | head -n 1 | cut -d'"' -f4
}

# Enrol this machine and get the token it will report with.
#
# One request, whichever kind of token was handed in: the dashboard builds the
# command with a project token, update.sh passes back the server token this
# machine already holds. The API knows which is which, so the installer does
# not have to guess — and a token it rejects stops the install here, before
# anything is written.
resolve_token() {
	local http_code api_message

	http_code=$(curl -s -o "$RESPONSE_FILE" -w '%{http_code}' \
		-X POST -H "Content-Type: application/json" \
		-d "{\"token\":\"$TOKEN\",\"name\":\"$(hostname)\"}" \
		"$ENDPOINT/agent/enroll")

	case "$http_code" in
	200)
		token=$(json_field token)
		[ -n "$token" ] || fail "Could not read the server token from the API response"

		if grep -q '"created":[[:space:]]*true' "$RESPONSE_FILE"; then
			echo -e "|   Registered this server with your project\n|"
		else
			echo -e "|   Reusing the registration this machine already has\n|"
		fi
		;;
	401)
		fail "Invalid token. Copy a fresh installation command from your Netweak dashboard"
		;;
	403)
		api_message=$(json_field message)
		fail "${api_message:-Plan limit reached}"
		;;
	*)
		fail "Could not enrol this server with the API (HTTP $http_code)"
		;;
	esac
}

# Check if crontab is installed
if [ -z "$(command -v crontab)" ]; then

	# Confirm crontab installation
	echo "|" && read -r -p "|   Crontab is required and could not be found. Do you want to install it? [Y/n] " input_variable_install

	# Attempt to install crontab
	if [ -z "$input_variable_install" ] || [ "$input_variable_install" == "Y" ] || [ "$input_variable_install" == "y" ]; then
		if [ -n "$(command -v apt-get)" ]; then
			echo -e "|\n|   Notice: Installing required package 'cron' via 'apt-get'"
			apt-get -y update
			apt-get -y install cron
		elif [ -n "$(command -v yum)" ]; then
			echo -e "|\n|   Notice: Installing required package 'cronie' via 'yum'"
			yum -y install cronie

			if [ -z "$(command -v crontab)" ]; then
				echo -e "|\n|   Notice: Installing required package 'vixie-cron' via 'yum'"
				yum -y install vixie-cron
			fi
		elif [ -n "$(command -v pacman)" ]; then
			echo -e "|\n|   Notice: Installing required package 'cronie' via 'pacman'"
			pacman -S --noconfirm cronie
		fi
	fi

	if [ -z "$(command -v crontab)" ]; then
		# Show error
		echo -e "|\n|   Error: Crontab is required and could not be installed\n|"
		exit 1
	fi
fi

# Check if cron is running
if ! pgrep -x "cron|crond" >/dev/null 2>&1; then

	# Confirm cron service
	echo "|" && read -r -p "|   Cron is available but not running. Do you want to start it? [Y/n] " input_variable_service

	# Attempt to start cron
	if [ -z "$input_variable_service" ] || [ "$input_variable_service" == "Y" ] || [ "$input_variable_service" == "y" ]; then
		if [ -n "$(command -v apt-get)" ]; then
			echo -e "|\n|   Notice: Starting 'cron' via 'service'"
			service cron start
		elif [ -n "$(command -v yum)" ]; then
			echo -e "|\n|   Notice: Starting 'crond' via 'service'"
			chkconfig crond on
			service crond start
		elif [ -n "$(command -v pacman)" ]; then
			echo -e "|\n|   Notice: Starting 'cronie' via 'systemctl'"
			systemctl start cronie
			systemctl enable cronie
		fi
	fi

	# Check if cron was started
	if ! pgrep -x "cron|crond" >/dev/null 2>&1; then
		# Show error
		echo -e "|\n|   Error: Cron is available but could not be started\n|"
		exit 1
	fi
fi

# Last thing before anything is written: a bad token here means an agent that
# installs cleanly and then reports into nowhere. Registering also consumes a
# plan slot, so it waits until the machine is known to be able to run the agent.
resolve_token

# Attempt to delete previous agent
if [ -f "/etc/$INSTALL_PATH/agent.sh" ]; then
	echo -e "|   Removing previous agent\n|"

	# Remove agent dir
	rm -Rf "/etc/${INSTALL_PATH:?}"

	# Remove cron entries and user
	if id -u "$INSTALL_PATH" >/dev/null 2>&1; then
		(crontab -u "$INSTALL_PATH" -l | grep -v "/etc/$INSTALL_PATH/") | crontab -u "$INSTALL_PATH" - && userdel "$INSTALL_PATH"
	else
		(crontab -u root -l | grep -v "/etc/$INSTALL_PATH/") | crontab -u root -
	fi
fi

# Create agent dir
mkdir -p "/etc/$INSTALL_PATH"

# Create log dir
mkdir -p "/etc/$INSTALL_PATH/log"

# Download agent files
DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://github.com/netweak/agent/raw/$BRANCH}"
for file in agent.sh lib.sh update.sh uninstall.sh config.conf README.md; do
	echo -e "|   Downloading $file to /etc/$INSTALL_PATH"
	if ! curl -fJLso "/etc/$INSTALL_PATH/$file" "$DOWNLOAD_BASE/$file"; then
		echo -e "|\n|   Error: Failed to download $file\n|"
		exit 1
	fi
	if [ ! -s "/etc/$INSTALL_PATH/$file" ]; then
		echo -e "|\n|   Error: Downloaded $file is empty\n|"
		exit 1
	fi
done

# Fill config file
sed -i "s|^token=.*|token=$token|" "/etc/$INSTALL_PATH/config.conf"
sed -i "s|^version=.*|version=$VERSION|" "/etc/$INSTALL_PATH/config.conf"
if [ "$ENDPOINT" != "https://api.netweak.com" ]; then
	sed -i "s|^endpoint=.*|endpoint=$ENDPOINT|" "/etc/$INSTALL_PATH/config.conf"
fi
if [ "$DEBUG" -eq 1 ]; then
	sed -i "s|^debug=.*|debug=1|" "/etc/$INSTALL_PATH/config.conf"
fi


# Create user
useradd "$INSTALL_PATH" -r -d "/etc/$INSTALL_PATH" -s /bin/false

# Modify user permissions
chown -R "$INSTALL_PATH":"$INSTALL_PATH" "/etc/$INSTALL_PATH" && chmod -R 700 "/etc/$INSTALL_PATH"

# Modify ping permissions
chmod +s "$(type -p ping)"

# Configure cron
crontab -u "$INSTALL_PATH" -l 2>/dev/null | {
	cat
	echo "* * * * * bash /etc/$INSTALL_PATH/agent.sh 2>> /etc/$INSTALL_PATH/log/error.log"
} | crontab -u "$INSTALL_PATH" -

# Report once now rather than leaving the server pending until cron next
# fires, up to a minute away. A failure here is not fatal: cron retries, and
# the token was already validated above.
echo -e "|   Sending the first report\n|"
su -s /bin/bash -c "bash '/etc/$INSTALL_PATH/agent.sh'" "$INSTALL_PATH" \
	2>>"/etc/$INSTALL_PATH/log/error.log" || true

# Show success
echo -e "|\n|   Success: The Netweak agent has been installed\n|"

# Attempt to delete installation script
if [ -f "$0" ]; then
	rm -f "$0"
fi
