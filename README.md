# IT Support Scripts

![Checks](https://github.com/Txmiloluwa/it-support-scripts/actions/workflows/checks.yml/badge.svg)

Practical scripts for common help desk tasks, written for **Linux and macOS (Bash)** and **Windows (PowerShell)**. Each one automates a job an IT support technician does by hand: diagnosing a slow machine, working out why "the internet is down", freeing up disk space and setting up accounts for new starters.

Every script is linted and tested automatically on Linux, macOS and Windows with GitHub Actions.

| Task | Linux / macOS | Windows |
|---|---|---|
| "My computer is slow": health report | `bash/system_health.sh` | `powershell/Get-SystemHealth.ps1` |
| "The internet isn't working": step-by-step diagnosis | `bash/network_check.sh` | `powershell/Test-NetworkHealth.ps1` |
| New starters: create accounts from a CSV | `bash/bulk_create_users.sh` | `powershell/New-BulkLocalUsers.ps1` |
| "My disk is full": find space, clear old temp files | `bash/disk_cleanup.sh` | |

## Safety first

Anything that changes a system is **safe by default**:

- `bulk_create_users.sh` and `disk_cleanup.sh` run as a **dry run** unless you pass `--apply` or `--delete`.
- Deleting files also needs you to type `YES` to confirm.
- `New-BulkLocalUsers.ps1` supports PowerShell's standard `-WhatIf`, so you can preview every change first.
- New accounts get a random temporary password and **must change it at first login**.

## The scripts

### System health report
Checks OS version, uptime, CPU load, memory, disk space and the busiest processes, then flags problems (a disk above 85% full, memory above 90%, CPU load above the number of cores).

```bash
./bash/system_health.sh
./bash/system_health.sh --disk-warn 90
```
```powershell
.\powershell\Get-SystemHealth.ps1 -DiskWarnPercent 90
```

### Network check
Tests the connection from the inside out, the same order a help desk would, so the **first failure shows where the problem is**:

1. Does the machine have an IP address? (A `169.254.x.x` address means the router's DHCP did not answer.)
2. Does the router (default gateway) respond?
3. Does DNS work (can names be turned into IP addresses)?
4. Is the internet reachable by IP, skipping DNS?
5. Does a real website load over HTTPS?

Each failure comes with its most likely cause.

```bash
./bash/network_check.sh bbc.co.uk
```

### Bulk user creation
Reads `examples/new_starters.csv` (`username,full_name,group`), skips invalid or existing usernames with a clear reason, creates the rest, adds them to their group and forces a password change at first login.

```bash
./bash/bulk_create_users.sh examples/new_starters.csv               # preview
sudo ./bash/bulk_create_users.sh examples/new_starters.csv --apply  # Linux only
```
```powershell
.\powershell\New-BulkLocalUsers.ps1 -CsvPath examples\new_starters.csv -WhatIf
.\powershell\New-BulkLocalUsers.ps1 -CsvPath examples\new_starters.csv   # run as Administrator
```

### Disk clean-up
Lists the biggest folders and files over 100 MB, and finds `.tmp`, `.log` and `.cache` files older than 30 days.

```bash
./bash/disk_cleanup.sh ~/Downloads
./bash/disk_cleanup.sh ~/Downloads --days 60 --delete
```

## Testing

GitHub Actions runs on every push:

- **ShellCheck** on all Bash scripts and **PSScriptAnalyzer** on all PowerShell scripts, with zero warnings allowed
- the Bash scripts on **Ubuntu and macOS**, including a real account creation on Linux that checks the user exists and must change their password
- a clean-up test that confirms the dry run deletes nothing and `--delete` removes only old temp files
- the PowerShell scripts on **Windows**, with user creation in `-WhatIf` mode

## Lessons learned

- **macOS ships with Bash 3.2**, which has no `mapfile`, so the scripts read files with a `while read` loop to work on both systems.
- **`set -o pipefail` and `head`**: piping endless `/dev/urandom` into `head` makes the first command exit with SIGPIPE, which `pipefail` treats as an error and silently stops the script. The password generator reads a fixed 300 bytes first to avoid it. Testing account creation for real is what caught this.
- **Commands differ between systems** (`ping -W` vs `ping -t`, `ip route` vs `route get`, `/proc/meminfo` vs `vm_stat`), so each script checks `uname` first.
