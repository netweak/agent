#!/bin/bash

# Set env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Default values
VERSION="1.2.1"
ENDPOINT="https://api.netweak.com"
BRANCH="main"
NETWEAK="netweak"

# Function to display usage information
usage() {
	echo -e "| Usage: bash $0 [options] <token>\n|"
	echo -e "| Options:"
	echo -e "|   -e, --endpoint <url>    API endpoint (default: https://api.netweak.com)"
	echo -e "|   -b, --branch <name>     Branch to install from (default: main)\n|"
	exit 1
}

# Parse command line arguments
PARSED_ARGS=$(getopt -o e:b: --long endpoint:,branch: -n "$0" -- "$@")
if [ $? -ne 0 ]; then
	usage
fi

eval set -- "$PARSED_ARGS"

# Parse arguments
while true; do
	case "$1" in
	-e | --endpoint)
		ENDPOINT="$2"
		shift 2
		;;
	-b | --branch)
		BRANCH="$2"
		shift 2
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

# Get token
TOKEN="$1"

# If branch is not main, append it to the folder name
if [ "$BRANCH" != "main" ]; then
	SAFE_BRANCH=$(echo "$BRANCH" | sed 's|/|-|g' | sed 's|[^a-zA-Z0-9_-]||g')
	NETWEAK="netweak-${SAFE_BRANCH}"
fi

# Prepare output
echo -e "|\n|   Netweak Installer\n|   ===================\n|"

# Check if user is root
if [ $(id -u) != "0" ]; then
	echo -e "|   Error: You need to be root to install the Netweak agent\n|"
	echo -e "|          The agent itself will NOT be running as root but instead under its own non-privileged user\n|"
	exit 1
fi

# Required parameter
if [ -z "$TOKEN" ]; then
	usage
fi

# Validate endpoint URL format
if ! [[ $ENDPOINT =~ ^https?:// ]]; then
	echo -e "| Error: Invalid endpoint URL format. Must start with http:// or https://\n|"
	exit 1
fi

# Validate branch name
if ! [[ $BRANCH =~ ^[a-zA-Z0-9_.-]+$ ]]; then
	echo -e "| Error: Invalid branch name. Only alphanumeric characters, dots, hyphens, and underscores are allowed.\n|"
	exit 1
fi

# Check for curl
if ! command -v curl >/dev/null 2>&1; then
	echo -e "|\n|   Error: curl is required but not installed\n|"
	exit 1
fi

# Exchange JIT token for agent token
if [[ $TOKEN == jit-* ]]; then
	# POST request to retrieve token
	response=$(curl -s -X POST -d "token=$TOKEN" "$ENDPOINT/agent/get-token")

	# Check if there's an error
	if [[ $? -ne 0 ]]; then
		echo -e "|\n| Error: Failed to retrieve token from API. Make sure your installation command is correct.\n|"
		exit 1
	fi

	# Extracting token from response
	token=$(echo "$response" | tr -d '\n')
else
	# Token doesn't start with "jit-", using it as is
	token=$TOKEN
fi

# Check if crontab is installed
if [ ! -n "$(command -v crontab)" ]; then

	# Confirm crontab installation
	echo "|" && read -p "|   Crontab is required and could not be found. Do you want to install it? [Y/n] " input_variable_install

	# Attempt to install crontab
	if [ -z $input_variable_install ] || [ $input_variable_install == "Y" ] || [ $input_variable_install == "y" ]; then
		if [ -n "$(command -v apt-get)" ]; then
			echo -e "|\n|   Notice: Installing required package 'cron' via 'apt-get'"
			apt-get -y update
			apt-get -y install cron
		elif [ -n "$(command -v yum)" ]; then
			echo -e "|\n|   Notice: Installing required package 'cronie' via 'yum'"
			yum -y install cronie

			if [ ! -n "$(command -v crontab)" ]; then
				echo -e "|\n|   Notice: Installing required package 'vixie-cron' via 'yum'"
				yum -y install vixie-cron
			fi
		elif [ -n "$(command -v pacman)" ]; then
			echo -e "|\n|   Notice: Installing required package 'cronie' via 'pacman'"
			pacman -S --noconfirm cronie
		fi
	fi

	if [ ! -n "$(command -v crontab)" ]; then
		# Show error
		echo -e "|\n|   Error: Crontab is required and could not be installed\n|"
		exit 1
	fi
fi

# Check if cron is running
if [ -z "$(ps -Al | grep cron | grep -v grep)" ]; then

	# Confirm cron service
	echo "|" && read -p "|   Cron is available but not running. Do you want to start it? [Y/n] " input_variable_service

	# Attempt to start cron
	if [ -z $input_variable_service ] || [ $input_variable_service == "Y" ] || [ $input_variable_service == "y" ]; then
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
	if [ -z "$(ps -Al | grep cron | grep -v grep)" ]; then
		# Show error
		echo -e "|\n|   Error: Cron is available but could not be started\n|"
		exit 1
	fi
fi

# Attempt to delete previous agent
if [ -f "/etc/$NETWEAK/agent.sh" ]; then
	echo -e "|   Removing previous agent\n|"

	# Remove agent dir
	rm -Rf "/etc/$NETWEAK"

	# Remove cron entry and user
	if id -u "$NETWEAK" >/dev/null 2>&1; then
		(crontab -u "$NETWEAK" -l | grep -v "/etc/$NETWEAK/agent.sh") | crontab -u "$NETWEAK" - && userdel "$NETWEAK"
	else
		(crontab -u root -l | grep -v "/etc/$NETWEAK/agent.sh") | crontab -u root -
	fi
fi

# Create agent dir
mkdir -p "/etc/$NETWEAK"

# Create log dir
mkdir -p "/etc/$NETWEAK/log"

# Download agent
echo -e "|   Downloading agent.sh to /etc/$NETWEAK"
if ! curl -JLso "/etc/$NETWEAK/agent.sh" "https://github.com/netweak/agent/raw/$BRANCH/agent.sh"; then
	echo -e "|\n|   Error: Failed to download agent.sh\n|"
	exit 1
fi

# Download heartbeat
echo -e "|   Downloading heartbeat.sh to /etc/$NETWEAK"
if ! curl -JLso "/etc/$NETWEAK/heartbeat.sh" "https://github.com/netweak/agent/raw/$BRANCH/heartbeat.sh"; then
	echo -e "|\n|   Error: Failed to download heartbeat.sh\n|"
	exit 1
fi

# Verify downloaded files exist and aren't empty
for file in "agent.sh" "heartbeat.sh"; do
	if [ ! -f "/etc/$NETWEAK/$file" ]; then
		echo -e "|\n|   Error: Failed to download $file\n|"
		exit 1
	fi
	if [ ! -s "/etc/$NETWEAK/$file" ]; then
		echo -e "|\n|   Error: Downloaded $file is empty\n|"
		exit 1
	fi
done

if [ -f "/etc/$NETWEAK/agent.sh" ]; then
	# Create auth file
	echo "$token" >"/etc/$NETWEAK/token.conf"

	# Create endpoint file if different from default
	if [ "$ENDPOINT" != "https://api.netweak.com" ]; then
		echo "$ENDPOINT" >"/etc/$NETWEAK/endpoint.conf"
	fi

	# Create version file
	echo "$VERSION" >"/etc/$NETWEAK/version"

	# Create user
	useradd "$NETWEAK" -r -d "/etc/$NETWEAK" -s /bin/false

	# Modify user permissions
	chown -R "$NETWEAK":"$NETWEAK" "/etc/$NETWEAK" && chmod -R 700 "/etc/$NETWEAK"

	# Modify ping permissions
	chmod +s $(type -p ping)

	# Configure cron
	crontab -u "$NETWEAK" -l 2>/dev/null | {
		cat
		echo "* * * * * bash /etc/$NETWEAK/heartbeat.sh > /etc/$NETWEAK/log/cron.log 2>&1"
	} | crontab -u "$NETWEAK" -
	crontab -u "$NETWEAK" -l 2>/dev/null | {
		cat
		echo "* * * * * bash /etc/$NETWEAK/agent.sh > /etc/$NETWEAK/log/cron.log 2>&1"
	} | crontab -u "$NETWEAK" -

	# Show success
	echo -e "|\n|   Success: The Netweak agent has been installed\n|"

	# Attempt to delete installation script
	if [ -f $0 ]; then
		rm -f $0
	fi
else
	# Show error
	echo -e "|\n|   Error: The Netweak agent could not be installed\n|"
fi
