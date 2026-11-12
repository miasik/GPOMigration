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
 GPO backup folder path
 destination domains and servers
 MigTableCSV files
##############################################################################>

# Working folder: the folder of this script. When run as a selection in ISE,
# $PSScriptRoot is empty and the current folder is used.
$WorkingFolder = If ($PSScriptRoot) {$PSScriptRoot} Else {$PWD.Path}
Set-Location $WorkingFolder

# Log of this run in the working folder. *.log files are ignored by git.
Start-Transcript -Path (Join-Path $WorkingFolder ("GPOImport_{0:yyyyMMdd-HHmmss}.log" -f (Get-Date)))

Import-Module GroupPolicy
Import-Module ActiveDirectory
Import-Module ".\GPOMigration" -Force

# This path must be absolute, not relative
$Path        = $PWD  # Current folder specified in Set-Location above
$BackupPath  = "$PWD\GPO Backup wingtiptoys.local 2014-08-06-09-11-37"

###############################################################################
# IMPORT
###############################################################################
$DestDomain  = 'cohovineyard.com'
$DestServer  = 'cvdcr2.cohovineyard.com'
$MigTableCSVPath = '.\MigTable_sample.csv'

# Check the migration table before anything is imported. This only writes a
# .migtable file in the working folder; nothing changes in the destination yet.
$MigTableCheck = New-GPOMigrationTable -DestDomain $DestDomain -Path $Path -BackupPath $BackupPath -MigTableCSVPath $MigTableCSVPath
Show-GPOMigrationTable -Path $MigTableCheck | Format-Table -AutoSize -Wrap | Out-String -Width 300
If ((Read-Host "Check the migration table above. Import into $DestDomain now? (y/n)") -ne 'y') {
    "Import cancelled."
    Stop-Transcript
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

Stop-Transcript






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