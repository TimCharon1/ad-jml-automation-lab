#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Joiner / Mover / Leaver automation for a lab Active Directory domain.
.EXAMPLE
    .\Invoke-JML.ps1 -Mode Setup
    .\Invoke-JML.ps1 -Mode Joiner -CsvPath .\users.csv
    .\Invoke-JML.ps1 -Mode Mover  -CsvPath .\movers.csv
    .\Invoke-JML.ps1 -Mode Leaver -CsvPath .\leavers.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Setup','Joiner','Mover','Leaver')]
    [string]$Mode,
    [string]$CsvPath
)

$ErrorActionPreference = 'Stop'

$domain      = Get-ADDomain
$domainDN    = $domain.DistinguishedName
$baseOU      = "OU=LabCorp,$domainDN"
$disabledOU  = "OU=Disabled,$baseOU"
$departments = 'IT','HR','Sales'
$logFile     = Join-Path $PSScriptRoot 'jml-log.csv'

function Write-Log {
    param($Action, $User, $Detail)
    [pscustomobject]@{
        Time   = (Get-Date -Format s)
        Action = $Action
        User   = $User
        Detail = $Detail
    } | Export-Csv -Path $logFile -Append -NoTypeInformation
    Write-Host ("{0,-12} {1,-12} {2}" -f $Action, $User, $Detail)
}

function Ensure-OU {
    param($Name, $Path)
    $dn = "OU=$Name,$Path"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'")) {
        New-ADOrganizationalUnit -Name $Name -Path $Path
        Write-Log 'CreateOU' $Name $dn
    }
}

function Invoke-Setup {
    Ensure-OU 'LabCorp' $domainDN
    foreach ($ou in ($departments + 'Groups' + 'Disabled')) { Ensure-OU $ou $baseOU }
    foreach ($d in $departments) {
        $g = "SG-$d"
        if (-not (Get-ADGroup -Filter "Name -eq '$g'")) {
            New-ADGroup -Name $g -GroupScope Global -GroupCategory Security `
                -Path "OU=Groups,$baseOU" -Description "$d department"
            Write-Log 'CreateGroup' $g 'OU=Groups'
        }
    }
}

function Invoke-Joiner {
    $password = Read-Host 'Initial password for new users' -AsSecureString
    foreach ($u in Import-Csv $CsvPath) {
        try {
            if (Get-ADUser -Filter "SamAccountName -eq '$($u.Username)'") {
                Write-Log 'Skip' $u.Username 'already exists'
                continue
            }
            $fullName = "$($u.FirstName) $($u.LastName)"
            New-ADUser -Name $fullName -DisplayName $fullName `
                -GivenName $u.FirstName -Surname $u.LastName `
                -SamAccountName $u.Username `
                -UserPrincipalName "$($u.Username)@$($domain.DNSRoot)" `
                -Title $u.Title -Department $u.Department `
                -Path "OU=$($u.Department),$baseOU" `
                -AccountPassword $password -ChangePasswordAtLogon $true -Enabled $true
            Add-ADGroupMember -Identity "SG-$($u.Department)" -Members $u.Username
            Write-Log 'Joiner' $u.Username "OU=$($u.Department); SG-$($u.Department)"
        }
        catch { Write-Log 'ERROR' $u.Username $_.Exception.Message }
    }
}

function Invoke-Mover {
    foreach ($m in Import-Csv $CsvPath) {
        try {
            $user = Get-ADUser -Identity $m.Username -Properties Department
            $old  = $user.Department
            if ($old) { Remove-ADGroupMember -Identity "SG-$old" -Members $user -Confirm:$false }
            Add-ADGroupMember -Identity "SG-$($m.NewDepartment)" -Members $user
            Set-ADUser -Identity $user -Department $m.NewDepartment
            # Move last: the object's DN changes after the move
            Move-ADObject -Identity $user.DistinguishedName -TargetPath "OU=$($m.NewDepartment),$baseOU"
            Write-Log 'Mover' $m.Username "$old -> $($m.NewDepartment)"
        }
        catch { Write-Log 'ERROR' $m.Username $_.Exception.Message }
    }
}

function Invoke-Leaver {
    foreach ($l in Import-Csv $CsvPath) {
        try {
            $user = Get-ADUser -Identity $l.Username -Properties MemberOf
            Disable-ADAccount -Identity $user
            foreach ($groupDN in $user.MemberOf) {
                Remove-ADGroupMember -Identity $groupDN -Members $user -Confirm:$false
            }
            Set-ADUser -Identity $user -Description "Disabled $(Get-Date -Format yyyy-MM-dd) - leaver"
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $disabledOU
            Write-Log 'Leaver' $l.Username 'disabled, groups removed, moved to Disabled OU'
        }
        catch { Write-Log 'ERROR' $l.Username $_.Exception.Message }
    }
}

if ($Mode -ne 'Setup' -and -not $CsvPath) { throw "-CsvPath is required for -Mode $Mode" }

switch ($Mode) {
    'Setup'  { Invoke-Setup }
    'Joiner' { Invoke-Joiner }
    'Mover'  { Invoke-Mover }
    'Leaver' { Invoke-Leaver }
}
