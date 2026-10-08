<#
.SYNOPSIS
    Step-by-step check for "the internet isn't working" on Windows.

.DESCRIPTION
    Works from the inside out, the same order a help desk would:
    IP address -> default gateway -> DNS -> internet -> website.
    The FIRST failing step shows where the problem is.

.PARAMETER Target
    Website to test. Default: www.google.com

.EXAMPLE
    .\Test-NetworkHealth.ps1
    .\Test-NetworkHealth.ps1 -Target bbc.co.uk
#>
[CmdletBinding()]
param(
    [string]$Target = 'www.google.com'
)

$script:failed = 0

function Write-Pass([string]$Message) { Write-Output "  [PASS] $Message" }
function Write-Fail([string]$Message, [string]$Cause) {
    Write-Output "  [FAIL] $Message"
    Write-Output "         Likely cause: $Cause"
    $script:failed++
}

function Test-Ping([string]$HostName) {
    # -Count 1 -Quiet returns $true/$false instead of a full report.
    Test-Connection -ComputerName $HostName -Count 1 -Quiet -ErrorAction SilentlyContinue
}

Write-Output "Network check ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))"
Write-Output ""

# 1. IP address --------------------------------------------------------------
Write-Output "1. Local IP address"
$config = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
$ip = $config.IPv4Address.IPAddress
if (-not $ip) {
    Write-Fail "No active network adapter with an IP address" "Wi-Fi is off, the cable is unplugged, or the adapter is disabled"
}
elseif ($ip -like '169.254.*') {
    Write-Fail "IP $ip is a self-assigned address" "the DHCP server (usually the router) did not respond"
}
else {
    Write-Pass "Adapter '$($config.InterfaceAlias)' has IP $ip"
}

# 2. Gateway -----------------------------------------------------------------
Write-Output "2. Default gateway (your router)"
$gateway = $config.IPv4DefaultGateway.NextHop
if (-not $gateway) {
    Write-Fail "No default gateway configured" "not connected to a network, or DHCP failed"
}
elseif (Test-Ping $gateway) {
    Write-Pass "Router $gateway responds"
}
else {
    Write-Fail "Router $gateway did not reply to ping" "router is down, or it is configured to ignore ping"
}

# 3. DNS ---------------------------------------------------------------------
Write-Output "3. DNS (turning names into IP addresses)"
try {
    $resolved = Resolve-DnsName -Name $Target -Type A -ErrorAction Stop | Where-Object IPAddress | Select-Object -First 1
    Write-Pass "$Target resolves to $($resolved.IPAddress)"
}
catch {
    Write-Fail "Could not resolve $Target" "DNS server unreachable or misconfigured; try 'ipconfig /flushdns' or DNS 1.1.1.1"
}

# 4. Internet by IP ----------------------------------------------------------
Write-Output "4. Internet connectivity (by IP, skipping DNS)"
if ((Test-Ping '1.1.1.1') -or (Test-Ping '8.8.8.8')) {
    Write-Pass "Public internet is reachable"
}
else {
    Write-Fail "Cannot reach 1.1.1.1 or 8.8.8.8" "no internet from the router, ISP outage, or a firewall blocking ping"
}

# 5. Website over HTTPS -------------------------------------------------------
Write-Output "5. Website (HTTPS, port 443)"
$https = Test-NetConnection -ComputerName $Target -Port 443 -WarningAction SilentlyContinue
if ($https.TcpTestSucceeded) {
    Write-Pass "Connected to $Target on port 443"
}
else {
    Write-Fail "Could not connect to $Target on port 443" "website down, proxy or firewall blocking HTTPS"
}

Write-Output ""
if ($script:failed -eq 0) {
    Write-Output "Result: all checks passed"
    exit 0
}
Write-Output "Result: $script:failed check(s) failed. Start fixing from the FIRST failure above."
exit 1
