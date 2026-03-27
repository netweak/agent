#!/bin/bash

# Set env
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Default values
VERSION="1.3"
ENDPOINT="${ENDPOINT:-https://api.netweak.com}"
BRANCH="main"
INSTALL_PATH="netweak"
DEBUG=0

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
		ENDPOINT="https://api.netweak.dev"
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

# Exchange team token for agent token
if [[ $TOKEN == team_* ]]; then
	echo -e "|   Exchanging team token for server token\n|"
	http_code=$(curl -s -o /tmp/netweak_response.txt -w '%{http_code}' \
		-X POST -H "Content-Type: application/json" \
		-d "{\"team_token\":\"$TOKEN\",\"name\":\"$(hostname)\"}" \
		"$ENDPOINT/agent/get-token")

	case "$http_code" in
		200)
			token=$(grep -o '"token":"[^"]*"' /tmp/netweak_response.txt | cut -d'"' -f4)
			if [ -z "$token" ]; then
				echo -e "|   Error: Could not parse token from API response\n|"
				rm -f /tmp/netweak_response.txt
				exit 1
			fi
			;;
		401)
			echo -e "|   Error: Invalid team token. Make sure your installation command is correct.\n|"
			rm -f /tmp/netweak_response.txt
			exit 1
			;;
		403)
			api_message=$(grep -o '"message":"[^"]*"' /tmp/netweak_response.txt | cut -d'"' -f4)
			echo -e "|   Error: ${api_message:-Plan limit reached}\n|"
			rm -f /tmp/netweak_response.txt
			exit 1
			;;
		422)
			echo -e "|   Error: Invalid parameters sent to API\n|"
			rm -f /tmp/netweak_response.txt
			exit 1
			;;
		*)
			echo -e "|   Error: Failed to retrieve token from API (HTTP $http_code)\n|"
			rm -f /tmp/netweak_response.txt
			exit 1
			;;
	esac
	rm -f /tmp/netweak_response.txt
else
	# Token is a direct agent token, using it as is
	token="$TOKEN"
fi

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

# Validate token
check_code=$(curl -s -o /dev/null -w '%{http_code}' \
	-X POST -H "Content-Type: application/json" \
	-d "{\"token\":\"$token\"}" "$ENDPOINT/agent/check-token")
if [ "$check_code" != "200" ]; then
	echo -e "|   Warning: Token validation failed (HTTP $check_code). The agent may not report correctly.\n|"
fi

# Show success
echo -e "|\n|   Success: The Netweak agent has been installed\n|"

# Attempt to delete installation script
if [ -f "$0" ]; then
	rm -f "$0"
fi
