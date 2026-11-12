<##############################################################################
Ashley McGlone
Microsoft Premier Field Engineer
April 2014
http://aka.ms/GoateePFE

Module for Group Policy migration.

Requirements / Setup
-Windows 7/2008 R2 (or above) RSAT with AD PowerShell cmdlets installed.
-GPMC with GroupPolicy module installed.
-Import-Module GroupPolicy
-Import-Module ActiveDirectory

These are the default permissions required unless specific permission
delegations have been created:
Domain Admins to create policies and link them.
Enterprise Admins if linking policies to sites.


LEGAL DISCLAIMER
This Sample Code is provided for the purpose of illustration only and is not
intended to be used in a production environment.  THIS SAMPLE CODE AND ANY
RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.  We grant You a
nonexclusive, royalty-free right to use and modify the Sample Code and to
reproduce and distribute the object code form of the Sample Code, provided
that You agree: (i) to not use Our name, logo, or trademarks to market Your
software product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is embedded;
and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and
against any claims or lawsuits, including attorneys’ fees, that arise or result
from the use or distribution of the Sample Code.
 
This posting is provided "AS IS" with no warranties, and confers no rights. Use
of included script samples are subject to the terms specified
at http://www.microsoft.com/info/cpyright.htm.
##########################################################################sdg#>



<##############################################################################
Setup

Your working folder path should include your MigrationTableCSV files, a copy
of this script, a copy of the GPOMigration.psm1 module file, and the GPO
backup folder from the export.

This example assumes that a backup will run under a source credential and server,
and the import will run under a destination credential and server.  Between these
two operations you will need to copy your working folder from one environment to
the other.

NOTE: Before running you will need at least one MigrationTableCSV file using
this format:
Source,Destination,Type
"OldDomain.FQDN","NewDomain.FQDN","Domain"
"OldDomainNETBIOSName","NewDomainNETBIOSName","Domain"
"\\foo\server","\\baz\server","UNC"

Modify the following to your needs:
 working folder path (the folder of this script by default)
 GPO backup folder path (the newest backup in the working folder by default)
 destination domains and servers (the current domain and its PDC emulator by default)
 MigTableCSV files (built from the source and destination domains by default)
##############################################################################>

# Working folder: the folder of this script. When run as a selection in ISE,
# $PSScriptRoot is empty and the current folder is used.
$WorkingFolder = If ($PSScriptRoot) {$PSScriptRoot} Else {$PWD.Path}
Set-Location $WorkingFolder

# Log of this run in the working folder. *.log files are ignored by git.
Start-Transcript -Path (Join-Path $WorkingFolder ("GPOImport_{0:yyyyMMdd-HHmmss}.log" -f (Get-Date)))
# Everything below runs inside try/finally, so the log is closed even after an error.
# (The body is not indented to keep the history of this file readable.)
try {

Import-Module GroupPolicy
Import-Module ActiveDirectory
Import-Module ".\GPOMigration" -Force

# This path must be absolute, not relative
$Path        = (Get-Location).ProviderPath  # Current folder; ProviderPath also works on a share
# Backup to import: the newest "GPO Backup ..." folder in the working folder, by the
# export time in its name (the folder date changes when the folder is copied).
# To use another one: $BackupPath = "$Path\GPO Backup wingtiptoys.local 2014-08-06-09-11-37"
$BackupPath  = Get-ChildItem -Path $Path -Directory -Filter 'GPO Backup *' |
    Sort-Object @{Expression = {If ($_.Name -match '(\d{4}(-\d{2}){5})$') {$Matches[1]} Else {''}}}, LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName
If (-not $BackupPath) {
    Write-Warning "No 'GPO Backup ...' folder in $Path. Copy the export here or set `$BackupPath."
    Return
}
"Backup: $BackupPath"

###############################################################################
# IMPORT
###############################################################################
# Destination: the domain of this computer and its PDC emulator. Replace with
# names to import into another domain, e.g.
# $DestDomain = 'cohovineyard.com'; $DestServer = 'cvdcr2.cohovineyard.com'
$DestDomain  = (Get-ADDomain -Current LocalComputer).DNSRoot
$DestServer  = (Get-ADDomain -Server $DestDomain).PDCEmulator
"Destination: $DestDomain, server $DestServer"

# Stop if the backup comes from this very domain (import run on the source side)
$SourceFile = Join-Path $BackupPath 'SourceDomain.csv'
If ((Test-Path $SourceFile) -and
    (Import-Csv $SourceFile -Encoding UTF8).DomainSID -eq (Get-ADDomain -Server $DestServer).DomainSID.Value) {
    Write-Warning "This backup was exported from $DestDomain itself. Run the import in the new domain."
    Return
}
# Migration table CSV. Leave empty to build it from the source domain (saved in the
# backup by the export) and the destination domain: FQDN and NetBIOS name, both as
# domains and as UNC paths (\\domain\NETLOGON, \\domain\SYSVOL, DFS namespaces).
# Set a file name to use your own CSV, for example with UNC paths:
# $MigTableCSVPath = '.\MigTable_sample.csv'
$MigTableCSVPath = ''
If (-not $MigTableCSVPath) {
    $SourceFile = Join-Path $BackupPath 'SourceDomain.csv'
    If (-not (Test-Path $SourceFile)) {
        Write-Warning "No SourceDomain.csv in the backup (made by an older version). Set `$MigTableCSVPath to your CSV."
        Return
    }
    $Source = Import-Csv $SourceFile -Encoding UTF8
    $Dest   = Get-ADDomain -Server $DestServer
    $MigTableCSVPath = Join-Path $Path ("MigTable_{0}-to-{1}.csv" -f $Source.DNSRoot, $Dest.DNSRoot)
    @(
        [pscustomobject]@{Source = $Source.DNSRoot;     Destination = $Dest.DNSRoot;     Type = 'Domain'}
        [pscustomobject]@{Source = $Source.NetBIOSName; Destination = $Dest.NetBIOSName; Type = 'Domain'}
        [pscustomobject]@{Source = "\\$($Source.DNSRoot)";     Destination = "\\$($Dest.DNSRoot)";     Type = 'UNC'}
        [pscustomobject]@{Source = "\\$($Source.NetBIOSName)"; Destination = "\\$($Dest.NetBIOSName)"; Type = 'UNC'}
    ) | Export-Csv $MigTableCSVPath -NoTypeInformation -Encoding UTF8
}
"Migration table CSV: $MigTableCSVPath"
Import-Csv $MigTableCSVPath -Encoding UTF8 | Format-Table -AutoSize | Out-String -Width 300

# Check the migration table before anything is imported. This only writes a
# .migtable file in the working folder; nothing changes in the destination yet.
$MigTableCheck = New-GPOMigrationTable -DestDomain $DestDomain -Path $Path -BackupPath $BackupPath -MigTableCSVPath $MigTableCSVPath
Show-GPOMigrationTable -Path $MigTableCheck | Format-Table -AutoSize -Wrap | Out-String -Width 300
# GPMC check of the table: accounts and paths it cannot resolve. No output is good.
"Migration table check (no output below is good):"
Test-GPOMigrationTable -Path $MigTableCheck | Format-List | Out-String -Width 300
If ((Read-Host "Check the migration table above. Import into $DestDomain now? (y/n)") -ne 'y') {
    "Import cancelled."
    Return
}

# Add -RemoveExisting to delete GPOs of the same name in the destination first
Start-GPOImport `
    -DestDomain $DestDomain `
    -DestServer $DestServer `
    -Path $Path `
    -BackupPath $BackupPath `
    -MigTableCSVPath $MigTableCSVPath `
    -CopyACL

} finally {
    Stop-Transcript
}






<#

###############################################################################
# DEV to QA
###############################################################################
$DestDomain  = 'qa.wingtiptoys.com'
$DestServer  = 'dc1.qa.wingtiptoys.com'
$MigTableCSVPath = '.\MigTable_DEV_to_QA.csv'

Start-GPOImport `
    -DestDomain $DestDomain `
    -DestServer $DestServer `
    -Path $Path `
    -BackupPath $BackupPath `
    -MigTableCSVPath $MigTableCSVPath `
    -CopyACL

###############################################################################
# DEV to PROD
###############################################################################
$DestDomain  = 'prod.wingtiptoys.com'
$DestServer  = 'dc1.prod.wingtiptoys.com'
$MigTableCSVPath = '.\MigTable_DEV_to_PROD.csv'

Start-GPOImport `
    -DestDomain $DestDomain `
    -DestServer $DestServer `
    -Path $Path `
    -BackupPath $BackupPath `
    -MigTableCSVPath $MigTableCSVPath `
    -CopyACL

###############################################################################
# END
###############################################################################

#>