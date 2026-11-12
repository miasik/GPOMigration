# AGENTS.md

Guidance for AI coding assistants working on this repository.

## What this is

A PowerShell module that migrates Group Policy Objects between Active Directory
domains and forests: backup, migration table, import, permissions (ACLs), WMI
filters, GPO links and their order. A maintained fork of the module by Ashley
McGlone (Microsoft, 2014), whose repository is no longer updated. The typical use
here is cloning the GPOs of one domain into a newly built domain in a new forest.

## Layout

- `GPOMigration/GPOMigration.psm1` - the module (all functions)
- `GPOMigration/GPOMigration.psd1` - manifest
- `GPOMigration/GPOMigration.psm1-Help.xml` - external help for the original functions
- `Call-GPOExport.ps1`, `Call-GPOImport.ps1` - example wrappers, run from their own folder;
  they log each run (`*.log`) and default to the current domain and its PDC emulator
- `MigTable_sample.csv` - sample migration table CSV
- `CHANGELOG.md` - every change with its reason and source

## Requirements

- Windows PowerShell 5.1 (also runs on PowerShell 3.0+). It must keep working in
  5.1: no PowerShell 7-only syntax (`? :`, `??`, `ForEach-Object -Parallel`, ...).
- RSAT: `GroupPolicy` and `ActiveDirectory` modules, GPMC (COM `GPMgmt.GPM`).

## Rules for changes

- **Encoding:** `.ps1`, `.psm1`, `.psd1` are UTF-8 with BOM, CRLF (see `.gitattributes`).
  Keep code ASCII-only: Windows PowerShell 5.1 reads a file without BOM as ANSI, and
  typographic quotes or dashes then break parsing. Do not re-save files in another encoding.
- **Do not change the Microsoft notice** in file headers.
- **Every change gets a CHANGELOG entry** under `[Unreleased]`: what, why, source. Mark
  behavior changes explicitly.
- **One change per branch and pull request.** This repository is a fork: GitHub proposes
  `GoateePFE/GPOMigration` as the base of a pull request. The base must be
  `miasik/GPOMigration`.
- **Never claim code is tested.** Only a run against real AD domains tests it. Parsing in
  PowerShell 7 on Linux catches syntax errors only; GPMC, AD cmdlets and `SecurityIdentifier`
  do not work there.
- Public repository: no real domain, server or account names in code, docs or samples.

## Known pitfalls (each one bit this project)

- **AD target:** pass `-Server` to every AD/GPO cmdlet. Without it they go to the domain of
  the logged-on user. The default `AD:` drive does the same - map a drive with
  `New-PSDrive -PSProvider ActiveDirectory -Server ...` for `Set-Acl`.
- **COM paths:** GPMC COM methods resolve relative paths against the process folder
  (usually `C:\Windows\system32`), not the PowerShell location. Pass full paths.
- **Case:** `-like`/`-match` ignore case, `String.Replace()` and `[regex]::Matches()` do not.
  GPMC writes NetBIOS names in upper case; `gPLink` may use `cn=` or `CN=`.
- **CSV encoding:** `Export-Csv` in 5.1 defaults to ASCII. Always use `-Encoding UTF8` on
  both `Export-Csv` and `Import-Csv`.
- **-WhatIf:** in a function with `SupportsShouldProcess`, `ForEach-Object <PropertyName>`
  also honors `-WhatIf` and returns nothing. Use `Select-Object -ExpandProperty`.
- **Permissions are copied by SID,** never by bare name (a bare name resolves in the domain
  of the computer running the script, and localized group names differ). Well-known SIDs
  as is, built-in domain groups by RID, other domains as is, the rest via the migration table.
- **Migration tables do not cover Group Policy Preferences** (GPMC limitation).
- **Link order** is not in GPO backups; it is the `gPLink` attribute of each OU, where the
  last entry has link order 1.
