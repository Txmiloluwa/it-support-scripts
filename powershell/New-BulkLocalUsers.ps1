<#
.SYNOPSIS
    Create Windows local user accounts from a CSV file (e.g. new starters).

.DESCRIPTION
    Reads a CSV with the columns username,full_name,group. For each valid,
    new username it creates a local account with a random temporary password,
    adds it to the group (creating the group if needed) and forces a password
    change at first login.

    Supports -WhatIf: run with -WhatIf first to see what would happen without
    changing anything. Creating accounts requires an Administrator PowerShell.

.PARAMETER CsvPath
    Path to the CSV file.

.EXAMPLE
    .\New-BulkLocalUsers.ps1 -CsvPath ..\examples\new_starters.csv -WhatIf
    .\New-BulkLocalUsers.ps1 -CsvPath ..\examples\new_starters.csv
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$CsvPath
)

function Get-RandomPassword {
    # 14 characters from letters and digits, with at least one of each kind,
    # so it meets the default Windows password complexity rules.
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lower = 'abcdefghijkmnopqrstuvwxyz'.ToCharArray()
    $digit = '23456789'.ToCharArray()
    $all = $upper + $lower + $digit
    $chars = @(
        Get-Random -InputObject $upper
        Get-Random -InputObject $lower
        Get-Random -InputObject $digit
    ) + (1..11 | ForEach-Object { Get-Random -InputObject $all })
    -join ($chars | Sort-Object { Get-Random })
}

$rows = @(Import-Csv -Path $CsvPath)
if ($rows.Count -eq 0) {
    throw "CSV has no data rows: $CsvPath"
}
$required = 'username', 'full_name', 'group'
$missing = $required | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name }
if ($missing) {
    throw "CSV is missing column(s): $($missing -join ', ')"
}

$created = 0
$skipped = 0
$line = 1
$passwords = [System.Collections.Generic.List[object]]::new()
foreach ($row in $rows) {
    $line++
    $username = $row.username.Trim()
    $group = $row.group.Trim()

    # Windows local usernames: max 20 characters, none of these: " / \ [ ] : ; | = , + * ? < > @ or spaces.
    if ($username -notmatch '^[A-Za-z0-9._-]{1,20}$') {
        Write-Output "  Line ${line}: SKIPPED '$username' (invalid username)"
        $skipped++
        continue
    }
    if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
        Write-Output "  Line ${line}: SKIPPED '$username' (user already exists)"
        $skipped++
        continue
    }

    if ($PSCmdlet.ShouldProcess($username, "Create local user in group '$group'")) {
        if (-not (Get-LocalGroup -Name $group -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $group | Out-Null
        }
        $plain = Get-RandomPassword
        # Build a SecureString one character at a time (avoids ConvertTo-SecureString -AsPlainText).
        $secure = [System.Security.SecureString]::new()
        foreach ($c in $plain.ToCharArray()) { $secure.AppendChar($c) }
        New-LocalUser -Name $username -FullName $row.full_name -Password $secure -ErrorAction Stop | Out-Null
        Add-LocalGroupMember -Group $group -Member $username
        # Force a password change at first login.
        & net.exe user $username /logonpasswordchg:yes | Out-Null
        Write-Output "  Line ${line}: CREATED $username ($($row.full_name)) in group '$group'"
        $passwords.Add([pscustomobject]@{ Username = $username; TemporaryPassword = $plain })
    }
    $created++
}

Write-Output ""
Write-Output "Done: $created processed, $skipped skipped."
if ($passwords.Count -gt 0) {
    Write-Output "Temporary passwords (share each one securely, never by plain email):"
    $passwords | Format-Table -AutoSize | Out-String | Write-Output
}
