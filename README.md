<p align="center">
  <img src="https://netweak.com/img/logo/logo-dark.png" alt="Netweak" width="200">
</p>

<h3 align="center">Lightweight Linux Server Monitoring Agent</h3>

<p align="center">
  A minimal, dependency-free agent that collects system metrics and reports them to the <a href="https://netweak.com">Netweak</a> monitoring platform.
</p>

---

## Features

- **System** — uptime, load averages, process count, file descriptors, OS details
- **CPU & Memory** — core count, frequency, RAM/swap usage, top processes
- **Disk** — per-partition and total usage
- **Network** — active connections, interfaces, throughput (RX/TX), latency (EU/US/AS)
- Runs every minute via cron as a non-privileged `netweak` user
- Pure Bash — no external dependencies beyond standard Linux utilities

## Installation

Run the install command from your [Netweak dashboard](https://netweak.com). The installer requires root access and will create a dedicated `netweak` user with minimal permissions.

## What Gets Installed

| Path | Description |
|---|---|
| `/etc/netweak/agent.sh` | Main metrics collection script |
| `/etc/netweak/uninstall.sh` | Uninstall script |
| `/etc/netweak/config.conf` | Configuration (token, version, endpoint, debug) |
| `/etc/netweak/log/agent.log` | Application log (info, debug, errors) — auto-rotated at 1MB |
| `/etc/netweak/log/error.log` | Errors only (for quick diagnosis) |

A cron job runs `agent.sh` every minute under the `netweak` user.

## Requirements

- Linux (Debian/Ubuntu, CentOS/RHEL, Arch)
- `curl`
- `cron` (installed automatically if missing)

## Uninstall

```bash
sudo bash /etc/netweak/uninstall.sh
```

This will remove all cron jobs, delete `/etc/netweak/`, and remove the `netweak` user.

## Agent Payload Specification

### `POST /agent/report`

Full system metrics report sent every minute by `agent.sh`.

```json
{
  "token": "string — agent authentication token",
  "timestamp": 1711540800,
  "version": "string — agent version (e.g. \"1.3\")",
  "uptime": 123456,
  "sessions": 2,
  "processes": 145,
  "processes_array": "string — semicolon-delimited process list (user cpu rss cmd;...)",
  "file_handles": 1024,
  "file_handles_limit": 65536,
  "os_kernel": "string — kernel version (e.g. \"5.15.0-91-generic\")",
  "os_name": "string — OS name (e.g. \"Ubuntu 22.04.3 LTS\")",
  "os_arch": "string — architecture (\"x64\", \"x86\", \"aarch64\", ...)",
  "cpu_name": "string — CPU model name",
  "cpu_cores": 4,
  "cpu_freq": "string — CPU frequency in MHz",
  "ram_total": 8388608000,
  "ram_usage": 4194304000,
  "swap_total": 2147483648,
  "swap_usage": 104857600,
  "disk_array": "string — semicolon-delimited disk list (device total used;...)",
  "disk_total": 107374182400,
  "disk_usage": 53687091200,
  "connections": 42,
  "nic": "string — primary network interface name (e.g. \"eth0\")",
  "ipv4": "string — IPv4 address",
  "ipv6": "string — IPv6 address or \"N/A\"",
  "rx": 123456789,
  "tx": 987654321,
  "rx_gap": 12345,
  "tx_gap": 54321,
  "load": "string — load averages (e.g. \"0.50 0.75 0.60\")",
  "load_cpu": 45,
  "load_io": 12,
  "ping_eu": "string — latency to ping-eu.netweak.com in ms",
  "ping_us": "string — latency to ping-us.netweak.com in ms",
  "ping_as": "string — latency to ping-as.netweak.com in ms"
}
```

| Field | Type | Unit | Description |
|---|---|---|---|
| `token` | string | — | Agent authentication token |
| `timestamp` | integer | Unix epoch (seconds) | When the data was collected. Use to discard stale reports. |
| `version` | string | — | Agent version from config |
| `uptime` | integer | seconds | System uptime |
| `sessions` | integer | count | Active login sessions (`who`) |
| `processes` | integer | count | Total process count |
| `processes_array` | string | — | Semicolon-delimited list: `user cpu rss cmd;...` sorted by CPU/RSS desc |
| `file_handles` | integer | count | Open file descriptors |
| `file_handles_limit` | integer | count | Max file descriptors |
| `os_kernel` | string | — | Kernel version (`uname -r`) |
| `os_name` | string | — | OS distribution name |
| `os_arch` | string | — | CPU architecture (`x64`, `x86`, `aarch64`, ...) |
| `cpu_name` | string | — | CPU model name |
| `cpu_cores` | integer | count | Number of CPU cores |
| `cpu_freq` | string | MHz | CPU clock frequency |
| `ram_total` | integer | bytes | Total RAM |
| `ram_usage` | integer | bytes | Used RAM (total - free - cached - buffers) |
| `swap_total` | integer | bytes | Total swap |
| `swap_usage` | integer | bytes | Used swap |
| `disk_array` | string | — | Semicolon-delimited list: `device total used;...` (bytes) |
| `disk_total` | integer | bytes | Total disk space |
| `disk_usage` | integer | bytes | Used disk space |
| `connections` | integer | count | Active TCP/UDP connections |
| `nic` | string | — | Primary network interface name |
| `ipv4` | string | — | IPv4 address on primary NIC |
| `ipv6` | string | — | IPv6 address on primary NIC, or `"N/A"` |
| `rx` | integer | bytes | Total bytes received (cumulative since boot) |
| `tx` | integer | bytes | Total bytes transmitted (cumulative since boot) |
| `rx_gap` | integer | bytes | Bytes received since last report |
| `tx_gap` | integer | bytes | Bytes transmitted since last report |
| `load` | string | — | Space-separated 1/5/15 min load averages |
| `load_cpu` | integer | percent (0-100) | CPU usage since last report |
| `load_io` | integer | percent (0-100) | I/O wait since last report |
| `ping_eu` | string | ms | Latency to EU ping endpoint |
| `ping_us` | string | ms | Latency to US ping endpoint |
| `ping_as` | string | ms | Latency to Asia ping endpoint |

### `POST /agent/get-token`

Exchanges a team token for a server token during installation. Called by `install.sh` when the token argument starts with `team_`.

```json
{
  "team_token": "string — team token (team_*)",
  "name": "string — server hostname (optional)"
}
```

| Status | Meaning | Agent action |
|---|---|---|
| 200 | Server created, token returned | Use the returned `token` for reporting |
| 401 | Invalid team token | Stop — the team token is wrong or revoked |
| 403 `PlanLimitReached` | Team's plan doesn't allow more servers | Stop and display the error message (includes billing link) |
| 422 | Validation error | Stop — missing/invalid parameters |

### `POST /agent/check-token`

Validates an existing server token. Called by `install.sh` after installation to verify the token is active.

```json
{
  "token": "string — server authentication token"
}
```

| Status | Meaning |
|---|---|
| 200 | Token is valid |
| 401 | Token is incorrect or server has been deleted |

### `POST /agent/heartbeat`

Lightweight liveness signal sent every minute by `agent.sh` before collecting metrics.

```json
{
  "token": "string — agent authentication token",
  "timestamp": 1711540800
}
```

| Field | Type | Unit | Description |
|---|---|---|---|
| `token` | string | — | Agent authentication token |
| `timestamp` | integer | Unix epoch (seconds) | When the heartbeat was sent |

## Testing

Tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System). After cloning, initialize submodules:

```bash
git submodule update --init --recursive
```

### Unit Tests

Run locally (macOS or Linux):

```bash
./tests/bats-core/bin/bats tests/unit/
```

### Integration Tests

Require Docker (Linux environment with mock `/proc`):

```bash
docker build -f tests/docker/Dockerfile.ubuntu -t netweak-test .
docker run --rm netweak-test bats tests/integration/
```

### Security Tests

JSON escaping tests run locally; permission tests require Docker:

```bash
./tests/bats-core/bin/bats tests/security/test_json_escape.bats
docker run --rm netweak-test bats tests/security/test_permissions.bats
```

### Lifecycle Tests

Install/uninstall/update tests across Ubuntu, Rocky Linux, and Arch:

```bash
docker build -f tests/docker/Dockerfile.ubuntu -t netweak-ubuntu .
docker build -f tests/docker/Dockerfile.centos -t netweak-centos .
docker build -f tests/docker/Dockerfile.arch -t netweak-arch .
docker run --rm netweak-ubuntu bats tests/lifecycle/
```

### CI

All tests run automatically via GitHub Actions on PRs to `develop` and `main`.

## License

Copyright © [Netweak](https://netweak.com)
