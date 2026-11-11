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

### Notes
- The module now needs PowerShell 3.0 or later (`Import-Csv -Encoding`).
- Backups made with an older version of this module may already contain `?` in
  `GPPermissions.csv`. Export them again with this version.
- If your own migration table CSV (`MigTable*.csv`) contains non-ASCII names,
  save it as UTF-8.

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
