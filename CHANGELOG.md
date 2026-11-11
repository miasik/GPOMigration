# Changelog

All notable changes to this fork are documented here.
The original module was written by Ashley McGlone (Microsoft PFE, "GoateePFE").
Original repository: https://github.com/GoateePFE/GPOMigration

## [Unreleased] - planned as 1.2

### Fixed
- Running from a computer outside the source or destination domain (for example,
  an admin forest). Several AD calls ignored `-SrceServer` / `-DestServer` and went
  to the domain of the logged-on user instead:
  - `Export-GPPermission`: `Get-ADObject` now uses `-Server $SrceServer`.
    Before, `GPPermissions.csv` came out empty. Source: reader comments of
    2015-11-25 and 2018-05-01 (LIHU).
  - `Invoke-BackupGPO`: the list of WMI filters is now read from the source domain.
  - `Import-GPPermission`: ACLs are read from and written to the destination DC.
    `Set-Acl` now uses a drive mapped to `-DestServer` instead of the default `AD:` drive.
  - `Set-GPWMIFilterFromBackup`: the GPO is looked up in the destination domain.
- `New-GPOMigrationTable`: domain local groups now get their domain name replaced
  like global groups and users. Before, they kept the source domain name and the
  import could not resolve them. Source: reader comments of 2015-10-09 and 2016-12-30.
- Non-ASCII names (Cyrillic, German umlauts and so on) in GPO names, groups and
  WMI filters. Windows PowerShell 5.1 `Export-Csv` writes ASCII by default, so such
  characters became `?` in `GPPermissions.csv` and `WMIFilter.csv`, and the import
  failed with warnings like `Cannot set: 'Dom?nen-Admins'`. Both files are now
  written and read as UTF-8. Source: reader comment of 2016-10-03 (Daniel).
- GPO backup XML files (`backup.xml`, `gpreport.xml`) are now loaded with
  `XmlDocument.Load`, which honors the file's own encoding, instead of `Get-Content`.
- `New-GPOMigrationTable`: domain names from the migration table CSV are now
  matched and replaced without regard to case. Before, the check ignored case but
  the replacement did not, so a CSV value `corp` matched `CORP\user` and then
  changed nothing - the entry silently kept the source domain. The sample CSV has
  NetBIOS names in lower case, so this happened with the sample as shipped.
  UNC paths are matched the same way.
- GPO permissions are now copied by SID instead of by name:
  - An account without a destination in the migration table was looked up by its
    bare name, which resolved in the domain of the computer running the script.
    Run from an admin forest, a GPO in the new domain could get an ACE for an
    admin forest group of the same name. Such ACEs are now skipped with a warning.
  - Accounts of different domains with the same name (`Domain Admins` of two
    domains) could match the same migration table entry. Entries are now matched
    by name and domain.
  - Built-in groups (Domain Admins, Domain Computers, Enterprise Admins...) are
    translated by RID, and well-known principals (Authenticated Users, SYSTEM,
    CREATOR OWNER, BUILTIN\...) by their SID. This works whatever the OS language;
    before, localized names like `Domänen-Admins` failed.
- `Invoke-ImportGPO`: *Authenticated Users* and *Domain Computers* get Read by SID.
  `Set-GPPermissions -TargetName 'Domain Computers'` failed on non-English DCs,
  where the group has a localized name.
- `Invoke-ImportGPO`: permissions are no longer copied to a GPO whose import failed.
- `Export-GPPermission`: inherited ACEs are no longer exported. Before, they were
  written to the destination GPO as explicit ACEs.
- `Import-GPPermission`: the ACL of each GPO is written once instead of once per ACE.

### Changed
- **Behavior change - entries of other domains.** The 2020 fork change that set
  the destination domain on every `name@domain` entry now applies only to entries
  of the source domain that the CSV did not translate. Entries of other domains
  and forests (trusted domains, an admin forest) are left as they are, with a
  warning `Not translated: ...`. Before, they were silently pointed at same-named
  accounts in the destination domain. Add such domains to the CSV if they must change.
- **Behavior change - existing GPOs are no longer deleted by default.**
  `Start-GPOImport` used to call `Invoke-RemoveGPO` every time, deleting GPOs of
  the same name in the destination together with their links, although the code
  comment called this step optional. It now runs only with the new switch
  `-RemoveExisting`. Without it, `Import-GPO` imports the settings into the existing
  GPO, which keeps its GUID and links.
- `Invoke-RemoveGPO` supports `-WhatIf` and `-Confirm`, and skips GPOs that do not
  exist in the destination instead of printing an error for each of them.
- **Behavior change - principals of other domains and forests in GPO permissions**
  (trusted domains, an admin forest) are copied with their SID as is and reported.
  The destination domain must trust their domain. The migration table is not used
  for them.

### Notes
- The module now needs PowerShell 3.0 or later (`Import-Csv -Encoding`).
- Backups made with an older version of this module may already contain `?` in
  `GPPermissions.csv`. Export them again with this version.
- If your own migration table CSV (`MigTable*.csv`) contains non-ASCII names,
  save it as UTF-8.
- `GPPermissions.csv` has new columns (`IdentitySID`, `SourceDomain`,
  `SourceDomainSID`, `SourceRootSID`). Backups exported with an older version
  cannot be imported with `-CopyACL`; export them again.

### Maintenance
- `Call-GPOExport.ps1`, `Call-GPOImport.ps1` and `GPOMigration.psd1` converted from
  UTF-16 to UTF-8 with BOM, like the module itself. Git and GitHub now show their
  changes line by line.
- Typographic quotes (`‘ ’ “ ”`) in module code replaced with plain `'` and `"`.
  They came from copying code out of a web page and only worked while the file
  kept its BOM.
- Added `.gitattributes`: CRLF line endings for PowerShell, XML, CSV and Markdown files.

## 1.1-fork - 2020-11-27

Changes to `GPOMigration/GPOMigration.psm1` based on reader comments under the
original blog post. The module manifest still reports version 1.1.

### Changed
- **Behavior change - GPO permissions after import.** `Invoke-ImportGPO` now runs
  `Set-GPPermissions -PermissionLevel GpoRead -Replace` for *Authenticated Users*
  and *Domain Computers* right after `Import-GPO`. Previously every imported GPO
  got *Authenticated Users: Read + Apply*, so security-filtered GPOs applied to
  everyone in the destination domain.
  With `-CopyACL` (the default in `Start-GPOImport`) the source ACEs are added on
  top, so a GPO that had *Authenticated Users: Apply* in the source keeps it.
  If you call `Invoke-ImportGPO` **without** `-CopyACL`, *Authenticated Users*
  will have Read only and the GPO will not apply until you set permissions.
  Domain Computers: Read also keeps user-side GPOs working after MS16-072.
  Source: comment by Jens Schroeder, 2017-09-19.

### Fixed
- `Import-GPPermission`: migration table entries of type `Unknown`
  (well-known principals such as *Authenticated Users*, *CREATOR OWNER*) are no
  longer looked up in AD - which always failed - and are resolved by name to a SID
  instead. Source: comment by Jens Schroeder, 2017-09-19.
- `New-GPOMigrationTable`: entries in UPN form (`name@domain`) get their suffix
  replaced with the destination domain.

### Other
- `GPOMigration.psm1` re-encoded from UTF-16 BE to UTF-8 with BOM. Because of this,
  GitHub shows commit a0d7b63 as a binary change.

## 1.1 - 2014-08-11 (original)

- WMI filter migration (`Export-WMIFilter`, `Import-WMIFilter`,
  `Set-GPWMIFilterFromBackup`, `Enable-ADSystemOnlyChange`).
- Module manifest; help moved to an external XML file.

## 1.0 - 2014-04-28 (original)

- First release: backup/import of GPOs, migration table automation from a CSV,
  GPO permission export/import including deny entries, GPO link import.
