<#
.SYNOPSIS
    Quick health report for a Windows machine.

.DESCRIPTION
    Shows OS version, uptime, CPU load, memory, disk space and the busiest
    processes, and flags anything above a warning threshold. A typical first
    step when a user reports "my PC is slow".

.PARAMETER DiskWarnPercent
    Warn when a drive is at least this full. Default: 85.

.EXAMPLE
    .\Get-SystemHealth.ps1
    .\Get-SystemHealth.ps1 -DiskWarnPercent 90
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$DiskWarnPercent = 85
)

$warnings = [System.Collections.Generic.List[string]]::new()

function Write-Section([string]$Title) {
    Write-Output ""
    Write-Output "== $Title =="
}

Write-Output "System health report for $env:COMPUTERNAME"
Write-Output "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# --- Operating system ---------------------------------------------------------
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$uptime = (Get-Date) - $os.LastBootUpTime
Write-Section "Operating system"
Write-Output "  $($os.Caption) (build $($os.BuildNumber))"
Write-Output ("  Uptime: {0} days, {1} hours, {2} minutes" -f $uptime.Days, $uptime.Hours, $uptime.Minutes)
if ($uptime.TotalDays -gt 14) {
    $warnings.Add("Not restarted for $([int]$uptime.TotalDays) days; a restart may clear pending updates")
}

# --- CPU ----------------------------------------------------------------------
$cpu = Get-CimInstance -ClassName Win32_Processor
$load = [int](($cpu | Measure-Object -Property LoadPercentage -Average).Average)
Write-Section "CPU"
Write-Output "  $(@($cpu)[0].Name.Trim())"
Write-Output "  Logical processors: $(($cpu | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum)"
Write-Output "  Current load: $load%"
if ($load -ge 90) { $warnings.Add("CPU load is $load%") }

# --- Memory -------------------------------------------------------------------
# Win32_OperatingSystem reports memory in kilobytes.
$totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
$freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
$usedPercent = [math]::Round((($totalMB - $freeMB) / $totalMB) * 100)
Write-Section "Memory"
Write-Output "  Total: $totalMB MB | Free: $freeMB MB | Used: $usedPercent%"
if ($usedPercent -gt 90) { $warnings.Add("Memory usage is $usedPercent%") }

# --- Disks --------------------------------------------------------------------
Write-Section "Disk usage (warning at $DiskWarnPercent% or more)"
# DriveType 3 = local fixed disk
$disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3"
foreach ($disk in $disks) {
    if (-not $disk.Size) { continue }
    $sizeGB = [math]::Round($disk.Size / 1GB, 1)
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
    $pct = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100)
    Write-Output ("  {0}  {1} GB free of {2} GB ({3}% used)" -f $disk.DeviceID, $freeGB, $sizeGB, $pct)
    if ($pct -ge $DiskWarnPercent) { $warnings.Add("Drive $($disk.DeviceID) is $pct% full") }
}

# --- Processes ----------------------------------------------------------------
Write-Section "Top 5 processes by memory"
Get-Process |
    Sort-Object -Property WorkingSet64 -Descending |
    Select-Object -First 5 -Property Id, ProcessName,
        @{ Name = 'MemoryMB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB) } } |
    Format-Table -AutoSize |
    Out-String |
    Write-Output

# --- Summary ------------------------------------------------------------------
Write-Section "Summary"
if ($warnings.Count -eq 0) {
    Write-Output "  OK: no problems found"
}
else {
    foreach ($w in $warnings) { Write-Output "  [WARNING] $w" }
}
