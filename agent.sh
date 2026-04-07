#!/bin/bash
# shellcheck disable=SC1090,SC1091,SC1001

# Ensure consistent PATH
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Source shared functions
source "$SCRIPT_DIR/lib.sh"

# Allow overriding /proc path for testing
PROC_DIR="${PROC_DIR:-/proc}"

# Prevent concurrent agent runs via flock
LOCK_FILE="$SCRIPT_DIR/agent.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
	exit 0
fi

# Read config
if [ -f "$SCRIPT_DIR/config.conf" ]; then
	source "$SCRIPT_DIR/config.conf"
else
	echo "Error: File $SCRIPT_DIR/config.conf is missing." >&2
	exit 1
fi

# Set defaults
ENDPOINT="${endpoint:-https://api.netweak.com}"
DEBUG="${debug:-0}"
# shellcheck disable=SC2154
auth="$token"

# Log directory
LOG_DIR="$SCRIPT_DIR/log"
LOG_FILE="$LOG_DIR/agent.log"
MAX_LOG_SIZE=1048576 # 1MB

# Rotate log if it exceeds max size
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null)" -gt "$MAX_LOG_SIZE" ] 2>/dev/null; then
	tail -n 500 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

# Logging
log() {
	echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# shellcheck disable=SC2329,SC2317
log_error() {
	echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE" "$LOG_DIR/error.log" >&2
}

debug_log() {
	if [ "$DEBUG" -eq 1 ]; then
		echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
	fi
}

# Send an API request with automatic termination
api_request() {
	local url="$1"
	local payload="$2"
	local tmp_file
	tmp_file=$(mktemp)
	echo "$payload" > "$tmp_file"

	debug_log "Sending request to $url"
	if [ -n "$(command -v timeout)" ]; then
		timeout -s SIGKILL 30 wget -q -o /dev/null -O /dev/null -T 25 --post-file="$tmp_file" --header="Content-Type: application/json" "$url"
	else
		wget -q -o /dev/null -O /dev/null -T 25 --post-file="$tmp_file" --header="Content-Type: application/json" "$url" &
		local wget_pid=$!
		local wget_counter=0
		local wget_timeout=30

		while kill -0 "$wget_pid" 2>/dev/null && (( wget_counter < wget_timeout )); do
			sleep 1
			(( wget_counter++ ))
		done

		kill -0 "$wget_pid" 2>/dev/null && kill -s SIGKILL "$wget_pid"
	fi

	rm -f "$tmp_file"
}

log "Agent started"
debug_log "Endpoint: $ENDPOINT"

# Send heartbeat first (lightweight, so the server knows we're alive)
debug_log "Sending heartbeat"
api_request "$ENDPOINT/agent/heartbeat" "{\"token\":\"${token}\",\"timestamp\":$(date +%s)}"
debug_log "Heartbeat sent"

# Agent version
version=$(prep "${version:-}")

# System uptime
uptime=$(int "$(awk '{ print $1 }' "$PROC_DIR/uptime")")

# Login session count
sessions=$(prep "$(who | wc -l)")

# Process count
processes=$(prep "$(ps axc | wc -l)")

# Process array
processes_array="$(ps axc -o uname:12,pcpu,rss,cmd --sort=-pcpu,-rss --noheaders --width 120)"
processes_array="$(echo "$processes_array" | grep -v " ps$" | sed 's/ \+ / /g; /^$/d' | tr "\n" ";")"

# File descriptors
file_handles=$(num "$(awk '{ print $1 }' "$PROC_DIR/sys/fs/file-nr")")
file_handles_limit=$(num "$(awk '{ print $3 }' "$PROC_DIR/sys/fs/file-nr")")

# OS details
os_kernel=$(prep "$(uname -r)")

if ls /etc/*release >/dev/null 2>&1; then
	os_name=$(prep "$(grep '^PRETTY_NAME=\|^NAME=\|^DISTRIB_ID=' /etc/*release | awk -F\= '{ print $2 }' | tr -d '"' | tac)")
fi

if [ -z "$os_name" ]; then
	if [ -e /etc/redhat-release ]; then
		os_name=$(prep "$(cat /etc/redhat-release)")
	elif [ -e /etc/debian_version ]; then
		os_name=$(prep "Debian $(cat /etc/debian_version)")
	fi

	if [ -z "$os_name" ]; then
		os_name=$(prep "$(uname -s)")
	fi
fi

case $(uname -m) in
x86_64)
	os_arch="x64"
	;;
i*86)
	os_arch="x86"
	;;
*)
	os_arch=$(prep "$(uname -m)")
	;;
esac

# CPU details
cpu_name=$(prep "$(grep 'model name' "$PROC_DIR/cpuinfo" | awk -F\: '{ print $2 }')")
cpu_cores=$(grep -c 'model name' "$PROC_DIR/cpuinfo")

if [ -z "$cpu_name" ]; then
	cpu_name=$(prep "$(grep 'vendor_id' "$PROC_DIR/cpuinfo" | awk -F\: '{ print $2 } END { if (!NR) print "N/A" }')")
	cpu_cores=$(grep -c 'vendor_id' "$PROC_DIR/cpuinfo")
fi

cpu_freq=$(prep "$(grep 'cpu MHz' "$PROC_DIR/cpuinfo" | awk -F\: '{ print $2 }')")

if [ -z "$cpu_freq" ]; then
	cpu_freq=$(num "$(lscpu | grep 'CPU MHz' | awk -F\: '{ print $2 }' | sed 's/^ *//; s/ *$//')")
fi

# RAM usage (in bytes)
ram_total=$(num "$(grep ^MemTotal: "$PROC_DIR/meminfo" | awk '{ print $2 }')")
ram_free=$(num "$(grep ^MemFree: "$PROC_DIR/meminfo" | awk '{ print $2 }')")
ram_cached=$(num "$(grep ^Cached: "$PROC_DIR/meminfo" | awk '{ print $2 }')")
ram_buffers=$(num "$(grep ^Buffers: "$PROC_DIR/meminfo" | awk '{ print $2 }')")
ram_usage=$(( (ram_total - (ram_free + ram_cached + ram_buffers)) * 1024 ))
ram_total=$(( ram_total * 1024 ))

# Swap usage (in bytes)
swap_total=$(num "$(grep ^SwapTotal: "$PROC_DIR/meminfo" | awk '{ print $2 }')")
swap_free=$(num "$(grep ^SwapFree: "$PROC_DIR/meminfo" | awk '{ print $2 }')")
swap_usage=$(( (swap_total - swap_free) * 1024 ))
swap_total=$(( swap_total * 1024 ))

# Disk usage (in bytes)
disk_total=$(num "$(($(df --output=size,source -B 1 | grep ' /' | awk '{ print $1 }' | sed -e :a -e '$!N;s/\n/+/;ta')))")
disk_usage=$(num "$(($(df --output=used,source -B 1 | grep ' /' | awk '{ print $1 }' | sed -e :a -e '$!N;s/\n/+/;ta')))")

# Disk array
disk_array=$(prep "$(df -P -B 1 | grep '^/' | awk '{ print $1" "$2" "$3";" }' | sed -e :a -e '$!N;s/\n/ /;ta' | awk '{ print $0 } END { if (!NR) print "N/A" }')")

# Active connections
if [ -n "$(command -v ss)" ]; then
	connections=$(num "$(ss -tun | tail -n +2 | wc -l)")
else
	connections=$(num "$(netstat -tun | tail -n +3 | wc -l)")
fi

# Network interface
nic=$(prep "$(ip route get 1.1.1.1 | grep dev | awk -F'dev' '{ print $2 }' | awk '{ print $1 }')")

if [ -z "$nic" ]; then
	nic=$(prep "$(ip link show | grep 'eth[0-9]' | awk '{ print $2 }' | tr -d ':')")
fi

# IP addresses and network usage
ipv4=$(prep "$(ip addr show "$nic" | grep 'inet ' | awk '{ print $2 }' | awk -F\/ '{ print $1 }' | grep -v '^127' | awk '{ print $0 } END { if (!NR) print "N/A" }')")
ipv6=$(prep "$(ip addr show "$nic" | grep 'inet6 ' | awk '{ print $2 }' | awk -F\/ '{ print $1 }' | grep -v '^::' | grep -v '^0000:' | grep -v '^fe80:' | awk '{ print $0 } END { if (!NR) print "N/A" }')")

if [ -d "/sys/class/net/$nic/statistics" ]; then
	read -r rx < "/sys/class/net/$nic/statistics/rx_bytes"
	read -r tx < "/sys/class/net/$nic/statistics/tx_bytes"
else
	rx=$(num "$(ip -s link show "$nic" | grep '[0-9]*' | grep -v '[A-Za-z]' | awk '{ print $1 }' | sed -n '1 p')")
	tx=$(num "$(ip -s link show "$nic" | grep '[0-9]*' | grep -v '[A-Za-z]' | awk '{ print $1 }' | sed -n '2 p')")
fi

# Average system load
load=$(prep "$(awk '{ print $1" "$2" "$3 }' "$PROC_DIR/loadavg")")

# Detailed system load calculation
time=$(date +%s)
read -ra stat <<< "$(head -n1 "$PROC_DIR/stat" | sed 's/[^0-9 ]*//g; s/^ *//')"
cpu=$(( stat[0] + stat[1] + stat[2] + stat[3] ))
io=$(( stat[3] + stat[4] ))
idle=${stat[3]}

if [ -e "$SCRIPT_DIR/cache" ]; then
	read -ra data < "$SCRIPT_DIR/cache"
	# shellcheck disable=SC2034
	interval=$(( time - data[0] ))
	cpu_gap=$(( cpu - data[1] ))
	io_gap=$(( io - data[2] ))
	idle_gap=$(( idle - data[3] ))

	if (( cpu_gap > 0 )); then
		load_cpu=$(( (1000 * (cpu_gap - idle_gap) / cpu_gap + 5) / 10 ))
	fi

	if (( io_gap > 0 )); then
		load_io=$(( (1000 * (io_gap - idle_gap) / io_gap + 5) / 10 ))
	fi

	if (( rx > data[4] )); then
		rx_gap=$(( rx - data[4] ))
	fi

	if (( tx > data[5] )); then
		tx_gap=$(( tx - data[5] ))
	fi
fi

# Cache current values for next-run delta calculations
echo "$time $cpu $io $idle $rx $tx" >"$SCRIPT_DIR/cache"

# Prepare load variables
rx_gap=$(num "$rx_gap")
tx_gap=$(num "$tx_gap")
load_cpu=$(num "$load_cpu")
load_io=$(num "$load_io")

# Network latency
ping_eu=$(num "$(timeout 10 ping -c 2 -w 2 ping-eu.netweak.com 2>/dev/null | grep rtt | cut -d'/' -f4 | awk '{ print $3 }')")
ping_us=$(num "$(timeout 10 ping -c 2 -w 2 ping-us.netweak.com 2>/dev/null | grep rtt | cut -d'/' -f4 | awk '{ print $3 }')")
ping_as=$(num "$(timeout 10 ping -c 2 -w 2 ping-as.netweak.com 2>/dev/null | grep rtt | cut -d'/' -f4 | awk '{ print $3 }')")

# Build JSON payload
data_post=$(cat <<EOF
{
	"token": "$(json_str "$auth")",
	"timestamp": $(date +%s),
	"version": "$(json_str "$version")",
	"uptime": $uptime,
	"sessions": $sessions,
	"processes": $processes,
	"processes_array": "$(json_str "$processes_array")",
	"file_handles": $file_handles,
	"file_handles_limit": $file_handles_limit,
	"os_kernel": "$(json_str "$os_kernel")",
	"os_name": "$(json_str "$os_name")",
	"os_arch": "$(json_str "$os_arch")",
	"cpu_name": "$(json_str "$cpu_name")",
	"cpu_cores": $cpu_cores,
	"cpu_freq": "$cpu_freq",
	"ram_total": $ram_total,
	"ram_usage": $ram_usage,
	"swap_total": $swap_total,
	"swap_usage": $swap_usage,
	"disk_array": "$(json_str "$disk_array")",
	"disk_total": $disk_total,
	"disk_usage": $disk_usage,
	"connections": $connections,
	"nic": "$(json_str "$nic")",
	"ipv4": "$(json_str "$ipv4")",
	"ipv6": "$(json_str "$ipv6")",
	"rx": $rx,
	"tx": $tx,
	"rx_gap": $rx_gap,
	"tx_gap": $tx_gap,
	"load": "$(json_str "$load")",
	"load_cpu": $load_cpu,
	"load_io": $load_io,
	"ping_eu": "$ping_eu",
	"ping_us": "$ping_us",
	"ping_as": "$ping_as"
}
EOF
)

# Send report
debug_log "Payload: $data_post"
api_request "$ENDPOINT/agent/report" "$data_post"

# Finished
log "Agent finished"
exit 0
