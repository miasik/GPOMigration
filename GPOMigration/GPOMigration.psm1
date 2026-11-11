<##############################################################################
Module for Group Policy migration. Version 1.1.
Ashley McGlone
Microsoft Premier Field Engineer
April 2014, Updated August 2014
http://aka.ms/GoateePFE

Requirements / Setup
-Windows 7/2008 R2 (or above) RSAT with AD PowerShell cmdlets installed
-GPMC with GroupPolicy module installed
-Import-Module GroupPolicy
-Import-Module ActiveDirectory

These are the default permissions required unless specific permission
delegations have been created:
-Domain Admins to create policies and link them
-Enterprise Admins if linking policies to sites

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


#.ExternalHelp GPOMigration.psm1-help.xml
function Invoke-BackupGPO {
Param(
    [Parameter(Mandatory=$true,
        ParameterSetName="All")]
    [Switch]
    $All, # Backup all GPOs
    [Parameter(Mandatory=$true,
        ValueFromPipelineByPropertyName=$true,
        ParameterSetName="DisplayName")]
    [String[]]
    $DisplayName, # Array of GPO DisplayNames to backup
    [Parameter(Mandatory=$true)]
    [String]
    $SrceDomain,
    [Parameter(Mandatory=$true)]
    [String]
    $SrceServer,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $Path # Base path where backup folder will be created
)
    $BackupPath = Join-Path $Path "\GPO Backup $SrceDomain $(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss')\"
    New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
    
    If ($All) {
        Backup-GPO -Server $SrceServer -Domain $SrceDomain -Path $BackupPath -All | Out-Null
    } Else {
        ForEach ($Name in $DisplayName) {
            Backup-GPO -Server $SrceServer -Domain $SrceDomain -Path $BackupPath -Name $Name | Out-Null
        }
    }

    # Backup WMI filters
    If ($All) {
        $WMIFilterNames = Get-GPO -All -Domain $SrceDomain -Server $SrceServer |
            Where-Object {$_.WmiFilter} |
            Select-Object -ExpandProperty WmiFilter |
            Select-Object -ExpandProperty Name -Unique
    } Else {
        $WMIFilterNames = Get-GPO -All -Domain $SrceDomain -Server $SrceServer |
            Where-Object {$DisplayName -contains $_.DisplayName -and $_.WmiFilter} |
            Select-Object -ExpandProperty WmiFilter |
            Select-Object -ExpandProperty Name -Unique
    }
    If ($WMIFilterNames) {
        Export-WMIFilter -Name $WMIFilterNames -SrceServer $SrceServer -Path $BackupPath
    } Else {
        Write-Host "No WMI filters to export."
    }

    return $BackupPath
}


#.ExternalHelp GPOMigration.psm1-help.xml
function Export-GPPermission {
Param(
    [Parameter(Mandatory=$true,
        ParameterSetName="All")]
    [Switch]
    $All, # Backup all GPOs
    [Parameter(Mandatory=$true,
        ValueFromPipelineByPropertyName=$true,
        ParameterSetName="DisplayName")]
    [String[]]
    $DisplayName, # Array of GPO DisplayNames to backup
    [Parameter(Mandatory=$true)]
    [String]
    $SrceDomain,
    [Parameter(Mandatory=$true)]
    [String]
    $SrceServer,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $Path
)
    $GPO_ACEs = @()
    
    If ($All) {
        $DisplayName = Get-GPO -Server $SrceServer -Domain $SrceDomain -All |
            Select-Object -ExpandProperty DisplayName
    }

    ForEach ($Name in $DisplayName) {
        $GPO = Get-GPO -Server $SrceServer -Domain $SrceDomain -Name $Name
        # Using the NTSecurityDescriptor attribute instead of calling Get-ACL
        $ACL = (Get-ADObject -Server $SrceServer -Identity $GPO.Path -Properties NTSecurityDescriptor |
            Select-Object -ExpandProperty NTSecurityDescriptor).Access

        $GPO_ACEs += $ACL | Select-Object `
                @{name='Name';expression={$Name}}, `
                @{name='Path';expression={$GPO.Path}}, `
                *                
    }
    
    $GPO_ACEs | Export-CSV (Join-Path $Path GPPermissions.csv) -NoTypeInformation -Encoding UTF8
}


#.ExternalHelp GPOMigration.psm1-help.xml
Function Export-WMIFilter {
Param(
    [Parameter(Mandatory=$true)]
    [String[]]
    $Name,
    [Parameter(Mandatory=$true)]
    [String]
    $SrceServer,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $Path
)
    # CN=SOM,CN=WMIPolicy,CN=System,DC=wingtiptoys,DC=local
    $WMIPath = "CN=SOM,CN=WMIPolicy,$((Get-ADDomain -Server $SrceServer).SystemsContainer)"

    Get-ADObject -Server $SrceServer -SearchBase $WMIPath -Filter {objectClass -eq 'msWMI-Som'} -Properties msWMI-Author, msWMI-Name, msWMI-Parm1, msWMI-Parm2 |
     Where-Object {$Name -contains $_."msWMI-Name"} |
     Select-Object msWMI-Author, msWMI-Name, msWMI-Parm1, msWMI-Parm2 |
     Export-CSV (Join-Path $Path WMIFilter.csv) -NoTypeInformation -Encoding UTF8
}


#.ExternalHelp GPOMigration.psm1-help.xml
Function New-GPOMigrationTable {
Param (
    [Parameter(Mandatory=$true)]
    [String]
    $DestDomain,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $Path = '.\',  # Working path to store migration tables and backups
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $BackupPath,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $MigTableCSVPath
)
        # Instead of manually editing multiple migration tables,
        # use a CSV template of search/replace values to update the
        # migration table by code.
        $MigTableCSV = Import-CSV $MigTableCSVPath
        $MigDomains  = $MigTableCSV | Where-Object {$_.Type -eq "Domain"}
        $MigUNCs     = $MigTableCSV | Where-Object {$_.Type -eq "UNC"}

        # Code adapted from GPMC VBScripts
        # This version uses a GPO backup to get the migration table data.

        $gpm = New-Object -ComObject GPMgmt.GPM
        $mt = $gpm.CreateMigrationTable()
        $Constants = $gpm.getConstants()
        $GPMBackupDir = $gpm.GetBackupDir($BackupPath)
        $GPMSearchCriteria = $gpm.CreateSearchCriteria()
        $BackupList = $GPMBackupDir.SearchBackups($GPMSearchCriteria)

        ForEach ($GPMBackup in $BackupList) {
            $szBackupDomain = $GPMBackup.GPODomain
            $mt.Add(0,$GPMBackup)
            $mt.Add($constants.ProcessSecurity,$GPMBackup)
        }

        $szSourceDomain = $GPMBackup.GPODomain

        ForEach ($Entry in $mt.GetEntries()) {

            Switch ($Entry.EntryType) {
                
                # Search/replace UNC paths from CSV file
                $Constants.EntryTypeUNCPath {
                    ForEach ($MigUNC in $MigUNCs) {
                        If ($Entry.Source -like "$($MigUNC.Source)*") {
                            $mt.UpdateDestination($Entry.Source, $Entry.Source.Replace("$($MigUNC.Source)","$($MigUNC.Destination)")) | Out-Null
                        }
                    }
                }

                # Search/replace domain names from CSV file
                # v3 {$_ -in $Constants.EntryTypeLocalGroup, $Constants.EntryTypeGlobalGroup, $Constants.EntryTypeUnknown} {
                {$Constants.EntryTypeUser, $Constants.EntryTypeGlobalGroup, $Constants.EntryTypeLocalGroup, $Constants.EntryTypeUnknown -contains $_} {
                    ForEach ($MigDomain in $MigDomains) {
                        If ($Entry.Source -like "*@$($MigDomain.Source)") {
                            $mt.UpdateDestination($Entry.Source, $Entry.Source.Replace("@$($MigDomain.Source)","@$($MigDomain.Destination)")) | Out-Null
                        } ElseIf ($Entry.Source -like "$($MigDomain.Source)\*") {
                            $mt.UpdateDestination($Entry.Source, $Entry.Source.Replace("$($MigDomain.Source)\","$($MigDomain.Destination)\")) | Out-Null
                        }
                    }
                }

                # In some scenarios like single-domain forest the Enterprise Admin universal group needs to be migrated.
                ### Need to add logic to ignore it in other cases, as it may not always need to be translated.
                # v3 {$_ -in $Constants.EntryTypeUniversalGroup} {
                {$Constants.EntryTypeUniversalGroup -contains $_} {
                    ForEach ($MigDomain in $MigDomains) {
                        If ($Entry.Source -like "*@$($MigDomain.Source)") {
                            $mt.UpdateDestination($Entry.Source, $Entry.Source.Replace("@$($MigDomain.Source)","@$($MigDomain.Destination)")) | Out-Null
                        } ElseIf ($Entry.Source -like "$($MigDomain.Source)\*") {
                            $mt.UpdateDestination($Entry.Source, $Entry.Source.Replace("$($MigDomain.Source)\","$($MigDomain.Destination)\")) | Out-Null
                        }
                    }
                }

            } # end switch
            if ($Entry.Source -like "*@*") {
                $mt.UpdateDestination($Entry.Source, (($Entry.Source -split("@"))[0]) + '@' +$DestDomain) | Out-Null
                }
        } # end foreach

        $MigTablePath = Join-Path -Path $Path -ChildPath "$szSourceDomain-to-$DestDomain.migtable"
        $mt.Save($MigTablePath)

        return $MigTablePath
}


#.ExternalHelp GPOMigration.psm1-help.xml
Function Show-GPOMigrationTable {
Param (
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $Path # Path for migration table
)
    $gpm = New-Object -ComObject GPMgmt.GPM
    $mt = $gpm.GetMigrationTable($Path)

    # http://technet.microsoft.com/en-us/library/cc739066(v=WS.10).aspx
    # $Constants = $gpm.getConstants()
    $mt.GetEntries() |
        Select-Object Source, `
        @{name='DestOption';expression={
            Switch ($_.DestinationOption) {
                0 {'SameAsSource'; break}
                1 {'None'; break}
                2 {'ByRelativeName'; break}
                3 {'Set'; break}
            }
        }}, `
        @{name='Type';expression={
            Switch ($_.EntryType) {
                0 {'User'; break}
                1 {'Computer'; break}
                2 {'LocalGroup'; break}
                3 {'GlobalGroup'; break}
                4 {'UniversalGroup'; break}
                5 {'UNCPath'; break}
                6 {'Unknown'; break}
            }
        }},
        Destination
}


#.ExternalHelp GPOMigration.psm1-help.xml
Function Test-GPOMigrationTable {
Param (
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $Path
)
    $gpm = New-Object -ComObject GPMgmt.GPM
    $mt = $gpm.GetMigrationTable($Path)
    $mt.Validate().Status
}


#.ExternalHelp GPOMigration.psm1-help.xml
Function Invoke-ImportGPO {
Param (
    [Parameter(Mandatory=$true)]
    [String]
    $DestDomain,
    [Parameter(Mandatory=$true)]
    [String]
    $DestServer,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $BackupPath,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $MigTablePath,
    [Parameter()]
    [Switch]
    $CopyACL
)
    $gpm = New-Object -ComObject GPMgmt.GPM
    $Constants = $gpm.getConstants()
    $GPMBackupDir = $gpm.GetBackupDir($BackupPath)
    $GPMSearchCriteria = $gpm.CreateSearchCriteria()
    $BackupList = $GPMBackupDir.SearchBackups($GPMSearchCriteria)

    ForEach ($GPMBackup in $BackupList) {
        <#
        ID             : {2DA3E56D-061C-4CB7-95D8-DCA4D023ACF5}
        GPOID          : {F9A98B0E-12A3-4A1B-AFE9-97CEB089FEBE}
        GPODomain      : FOO.COM
        GPODisplayName : Desktop Super Powers
        Timestamp      : 1/14/2014 1:55:36 PM
        Comment        : Desktop Super Powers
        BackupDir      : C:\temp\Backup\
        #>

        "Importing GPO: $($GPMBackup.GPODisplayName)"
        try {
            Import-GPO -Domain $DestDomain -Server $DestServer -BackupGpoName $GPMBackup.GPODisplayName -TargetName $GPMBackup.GPODisplayName -Path $BackupPath -MigrationTable $MigTablePath -CreateIfNeeded
            Set-GPPermissions -Domain $DestDomain -Server $DestServer -Name $GPMBackup.GPODisplayName -PermissionLevel 'GPOread' -TargetName 'Authenticated Users' -TargetType Group -Replace -Confirm: $false
		          Set-GPPermissions -Domain $DestDomain -Server $DestServer -Name $GPMBackup.GPODisplayName -PermissionLevel 'GPOread' -TargetName 'Domain Computers' -TargetType Group -Replace -Confirm: $false		
        }
        catch {
            If ($_.Exception.ToString().Contains('0x8007000D')) {
                ""
                $_.Exception
                "Error importing GPO: $($_.InvocationInfo.BoundParameters.Item('BackupGpoName'))"
                "One or more security principals (user, group, etc.) in the migration table are not found in the destination domain."
                ""
            } Else {
                ""
                "An import error occurred:"
                $_ | fl * -force
                $_.InvocationInfo.BoundParameters | fl * -force
                $_.Exception
                ""
            }
        } # End Catch

        # Migrate the ACLs
        # NOTE: This may not handle universal groups or groups from other domains.
        If ($CopyACL) {
            Import-GPPermission -DestDomain $DestDomain -DestServer $DestServer -DisplayName $GPMBackup.GPODisplayName -Path "$BackupPath\GPPermissions.csv" -MigTablePath $MigTablePath
        } # End If CopyACL
    } # End ForEach GPMBackup
} # End Function


#.ExternalHelp GPOMigration.psm1-help.xml
Function Import-WMIFilter {
Param (
    [Parameter(Mandatory=$true)]
    [String]
    $DestServer,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $Path
)
    $WMIExportFile = Join-Path -Path $Path -ChildPath 'WMIFilter.csv'
    If ((Test-Path $WMIExportFile) -eq $false) {

        Write-Warning "No WMI filters to import."

    } Else {
    
        $WMIImport = Import-Csv $WMIExportFile -Encoding UTF8
        $WMIPath = "CN=SOM,CN=WMIPolicy,$((Get-ADDomain -Server $DestServer).SystemsContainer)"

        $ExistingWMIFilters = Get-ADObject -Server $DestServer -SearchBase $WMIPath `
            -Filter {objectClass -eq 'msWMI-Som'} `
            -Properties msWMI-Author, msWMI-Name, msWMI-Parm1, msWMI-Parm2

        ForEach ($WMIFilter in $WMIImport) {

            If ($ExistingWMIFilters | Where-Object {$_.'msWMI-Name' -eq $WMIFilter.'msWMI-Name'}) {
                Write-Host "WMI filter already exists: $($WMIFilter."msWMI-Name")"
            } Else {
                $msWMICreationDate = (Get-Date).ToUniversalTime().ToString("yyyyMMddhhmmss.ffffff-000")
                $WMIGUID = "{$([System.Guid]::NewGuid())}"
    
                $Attr = @{
                    "msWMI-Name" = $WMIFilter."msWMI-Name";
                    "msWMI-Parm2" = $WMIFilter."msWMI-Parm2";
                    "msWMI-Author" = $WMIFilter."msWMI-Author";
                    "msWMI-ID"= $WMIGUID;
                    "instanceType" = 4;
                    "showInAdvancedViewOnly" = "TRUE";
                    "msWMI-ChangeDate" = $msWMICreationDate; 
                    "msWMI-CreationDate" = $msWMICreationDate
                }
    
                # The Description in the GUI (Parm1) may be null. If so, that will botch the New-ADObject.
                If ($WMIFilter."msWMI-Parm1") {
                    $Attr.Add("msWMI-Parm1",$WMIFilter."msWMI-Parm1")
                }

                $ADObject = New-ADObject -Name $WMIGUID -Type "msWMI-Som" -Path $WMIPath -OtherAttributes $Attr -Server $DestServer -PassThru
                Write-Host "Created WMI filter: $($WMIFilter."msWMI-Name")"
            }
        }
    } # End If No WMI filters
}


#.ExternalHelp GPOMigration.psm1-help.xml
Function Import-GPPermission {
Param (
    [Parameter(Mandatory=$true)]
    [String]
    $DestDomain,
    [Parameter(Mandatory=$true)]
    [String]
    $DestServer,
    [Parameter(Mandatory=$true,
        ValueFromPipelineByPropertyName=$true)]
    [String[]]
    $DisplayName,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $Path,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $MigTablePath
)
    $MigTable = Show-GPOMigrationTable -Path $MigTablePath |
        Select-Object *, `
            @{name='SourceName';expression={($_.Source -split '@')[0]}}, `
            @{name='SourceDomain';expression={($_.Source -split '@')[1]}}, `
            @{name='DestinationName';expression={($_.Destination -split '@')[0]}}, `
            @{name='DestinationDomain';expression={($_.Destination -split '@')[1]}}

    $GPO_ACEs_CSV = Import-Csv $Path -Encoding UTF8 |
        Select-Object *, `
            @{name='IDName';expression={($_.IdentityReference -split '\\')[-1]}}, `
            @{name='IDDomain';expression={($_.IdentityReference -split '\\')[0]}}

    <#
    Show-GPOMigrationTable -Path $MigTablePath | ft -auto

    Source                              DestOption   Type           Destination                       
    ------                              ----------   ----           -----------                       
    Administrators                      SameAsSource Unknown                                          
    Domain Admins@wingtiptoys.local     Set          GlobalGroup    Domain Admins@cohovineyard.com    
    fsogroup@wingtiptoys.local          Set          GlobalGroup    fsogroup@cohovineyard.com         
    Enterprise Admins@wingtiptoys.local Set          UniversalGroup Enterprise Admins@cohovineyard.com
    joebobtoo@wingtiptoys.local         Set          User           joebobtoo@cohovineyard.com        
    anlan@wingtiptoys.local             Set          User           anlan@cohovineyard.com            
    fsouser@wingtiptoys.local           Set          User           fsouser@cohovineyard.com          
    anhill@wingtiptoys.local            Set          User           anhill@cohovineyard.com           
    joebobfoo@wingtiptoys.local         Set          User           joebobfoo@cohovineyard.com 

    Selected and split...
    
    MigTable
    
    Source            : joebobfoo@wingtiptoys.local
    DestOption        : Set
    Type              : User
    Destination       : joebobfoo@cohovineyard.com
    SourceName        : joebobfoo
    SourceDomain      : wingtiptoys.local
    DestinationName   : joebobfoo
    DestinationDomain : cohovineyard.com       

    ACLs

    Name                  : Starter Computer
    Path                  : cn={FC18876F-2975-4638-B8DE-D83AB4415A51},cn=policies,c
                            n=system,DC=wingtiptoys,DC=local
    ActiveDirectoryRights : CreateChild, DeleteChild, Self, WriteProperty, DeleteTr
                            ee, Delete, GenericRead, WriteDacl, WriteOwner
    InheritanceType       : All
    ObjectType            : 00000000-0000-0000-0000-000000000000
    InheritedObjectType   : 00000000-0000-0000-0000-000000000000
    ObjectFlags           : None
    AccessControlType     : Allow
    IdentityReference     : WINGTIPTOYS\Enterprise Admins
    IsInherited           : False
    InheritanceFlags      : ContainerInherit
    PropagationFlags      : None
    IDName              * : Enterprise Admins
    IDDomain            * : WINGTIPTOYS
    #>
    # The default AD: drive points at the domain of the logged-on user.
    # Map a drive to the destination DC so Set-Acl writes to the right domain.
    # The drive is local to this function and disappears when it returns.
    New-PSDrive -Name GPOMigDest -PSProvider ActiveDirectory -Root '//RootDSE/' -Server $DestServer | Out-Null

    ForEach ($Name in $DisplayName) {

        "Importing GPO Permissions: $Name"
        
        $GPO = Get-GPO -Domain $DestDomain -Server $DestServer -DisplayName $Name

        ForEach ($ACE in ($GPO_ACEs_CSV | Where-Object {$_.Name -eq $Name})) {

            Write-Host "Setting GPO permission: '$($ACE.IDName)' on '$Name'"    

            # Find the CSV ACE identity name in the MigTable
            # Possible zero or one matches, should not be multiple
            $MigID = $MigTable | Where-Object {$_.SourceName -eq $ACE.IDName}
            
            # If entry, then attempt to set it
            If ($MigID -and $MigID.Type -ne "Unknown") {
                # Find the AD object based on the type listed in the MigTable
                $ADObject = $null

                Try {
                    Switch ($MigID.Type) {
                        'Unkown'          {$ADObject = $null; break}
                        'User'            {$ADObject = Get-ADUser -Identity $MigID.DestinationName -Server $MigID.DestinationDomain; break}
                        'Computer'        {$ADObject = Get-ADComputer -Identity $ACE.IDName -Server $DestDomain; <# Special handling #>; break}
                        'GlobalGroup'     {$ADObject = Get-ADGroup -Identity $MigID.DestinationName -Server $MigID.DestinationDomain; break}
                        'LocalGroup'      {$ADObject = Get-ADGroup -Identity $MigID.DestinationName -Server $MigID.DestinationDomain; break}
                        'UniversalGroup'  {$ADObject = Get-ADGroup -Identity $MigID.DestinationName -Server "$($MigID.DestinationDomain):3268"; break}
                        Default           {$ADObject = $null; break}
                    }
                }
                Catch {
                    # AD object not found. Warning written below.
                }
                
                # If we found the object, then attempt to set the permission.
                If ($ADObject) {

                    "Found ADObject $($ADObject.Name). Writing permission."
                    # Same effect as using Get-ACL "AD:\..."
                    $acl = $GPO | Select-Object -ExpandProperty Path | Get-ADObject -Server $DestServer -Properties NTSecurityDescriptor | Select-Object -ExpandProperty NTSecurityDescriptor
                    
                    $ObjectType = [GUID]$($ACE.ObjectType)
                    $InheritedObjectType = [GUID]$($ACE.InheritedObjectType)
                    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
                        $ADObject.SID, $ACE.ActiveDirectoryRights, $ACE.AccessControlType, $ObjectType, `
                        $ACE.InheritanceType, $InheritedObjectType
                    $acl.AddAccessRule($ace)
                    
                    # Commit the ACL
                    Set-Acl -Path "GPOMigDest:\$($GPO.Path)" -AclObject $acl
                
                } Else {
                # Else, Log failure to find security principal
                    Write-Warning "ADObject not found.  ACE not set: '$($ACE.IDName)' on '$Name'"    
                }
                
            } Else {
            # Else, attempt to set without migration table translation (ie. CREATOR OWNER, etc.)

                "Setting ACE without migration table translation: '$($ACE.IDName)' on '$Name'"

                $sid = $null
                Try {
                    $sid = (New-Object System.Security.Principal.NTAccount($ACE.IDName)).Translate([System.Security.Principal.SecurityIdentifier])
                }
                Catch {
                    Write-Warning "Error.  Cannot set: '$($ACE.IDName)' on '$Name'"
                }
                
                If ($sid) {
                
                    # Same effect as using Get-ACL "AD:\..."
                    $acl = $GPO | Select-Object -ExpandProperty Path | Get-ADObject -Server $DestServer -Properties NTSecurityDescriptor | Select-Object -ExpandProperty NTSecurityDescriptor

                    $ObjectType = [GUID]$($ACE.ObjectType)
                    $InheritedObjectType = [GUID]$($ACE.InheritedObjectType)
                    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
                        $sid, $ACE.ActiveDirectoryRights, $ACE.AccessControlType, $ObjectType, `
                        $ACE.InheritanceType, $InheritedObjectType
                    $acl.AddAccessRule($ace)
                    
                    # Commit the ACL
                    Set-Acl -Path "GPOMigDest:\$($GPO.Path)" -AclObject $acl
                }

            }
<#
            # This is how you would set permissions using the GPO cmdlets.
            # However, they do not support DENY permissions. Not cool.
                        
            If ($ACE.'Trustee-SidType' -eq 'WellKnownGroup') {
                $ACE.'Trustee-SidType' = 'Group'
            }

            Try {
                Set-GPPermissions                                                                                     `
                    -Name            $GPMBackup.GPODisplayName                                                        `
                    -PermissionLevel $([Microsoft.GroupPolicy.GPPermissionType]$ACE.Permission)                       `
                    -TargetName      $ACE.'Trustee-Name'                                                              `
                    -TargetType      $([Microsoft.GroupPolicy.Commands.PermissionTrusteeType]$ACE.'Trustee-SidType')  `
                    -Domain          $DestDomain                                                                      `
                    -Server          $DestServer                                                                      `
                    -Replace |
                Out-Null
            }
            Catch {
                Write-Warning "Unable to set the following GP permission: '$($ACE.'Trustee-Name')' on '$($GPMBackup.GPODisplayName)'`n$ACE`n$($_.Exception)"
            }
#>

""
        } # End ForEach ACE
        # Force the ACL changes to SYSVOL
        $GPO.MakeAclConsistent()
    } # End ForEach DisplayName
} # End Function


#.ExternalHelp GPOMigration.psm1-help.xml
Function Invoke-RemoveGPO {
Param (
    [Parameter(Mandatory=$true)]
    [String]
    $DestDomain,
    [Parameter(Mandatory=$true)]
    [String]
    $DestServer,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $BackupPath
)
    $gpm = New-Object -ComObject GPMgmt.GPM
    $Constants = $gpm.getConstants()
    $GPMBackupDir = $gpm.GetBackupDir($BackupPath)
    $GPMSearchCriteria = $gpm.CreateSearchCriteria()
    $BackupList = $GPMBackupDir.SearchBackups($GPMSearchCriteria)

    ForEach ($GPMBackup in $BackupList) {
        <#
        ID             : {2DA3E56D-061C-4CB7-95D8-DCA4D023ACF5}
        GPOID          : {F9A98B0E-12A3-4A1B-AFE9-97CEB089FEBE}
        GPODomain      : FOO.COM
        GPODisplayName : Desktop Super Powers
        Timestamp      : 1/14/2014 1:55:36 PM
        Comment        : Desktop Super Powers
        BackupDir      : C:\temp\Backup\
        #>

        Write-Host "From domain $DestDomain removing GPO: $($GPMBackup.GPODisplayName)"
        try {
            Remove-GPO -Domain $DestDomain -Server $DestServer -Name $GPMBackup.GPODisplayName -ErrorAction Stop
        }
        catch {
            $_.Exception
            Continue
        }
    }
}


#.ExternalHelp GPOMigration.psm1-help.xml
Function Import-GPLink {
Param (
    [Parameter(Mandatory=$true)]
    [String]
    $DestDomain,
    [Parameter(Mandatory=$true)]
    [String]
    $DestServer,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $BackupPath,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $MigTableCSVPath # Path for migration table source for automatic migtable generation
)
    $gpm = New-Object -ComObject GPMgmt.GPM
    $Constants = $gpm.getConstants()
    $GPMBackupDir = $gpm.GetBackupDir($BackupPath)
    $GPMSearchCriteria = $gpm.CreateSearchCriteria()
    $BackupList = $GPMBackupDir.SearchBackups($GPMSearchCriteria)

    $MigTableCSV = Import-CSV $MigTableCSVPath
    $MigDomains  = $MigTableCSV | Where-Object {$_.Type -eq "Domain"}        

    ForEach ($GPMBackup in $BackupList) {

        "`n`n$($GPMBackup.GPODisplayName)"

        <#
        ID             : {2DA3E56D-061C-4CB7-95D8-DCA4D023ACF5}
        GPOID          : {F9A98B0E-12A3-4A1B-AFE9-97CEB089FEBE}
        GPODomain      : FOO.COM
        GPODisplayName : Desktop Super Powers
        Timestamp      : 1/14/2014 1:55:36 PM
        Comment        : Desktop Super Powers
        BackupDir      : C:\temp\Backup\
        #>
        # XmlDocument.Load honors the BOM and the encoding declared in the file
        $GPReport = New-Object System.Xml.XmlDocument
        $GPReport.Load((Join-Path -Path $GPMBackup.BackupDir -ChildPath "$($GPMBackup.ID)\gpreport.xml"))
        
        $gPLinks = $null
        $gPLinks = $GPReport.GPO.LinksTo | Select-Object SOMName, SOMPath, Enabled, NoOverride
        # There may not be any gPLinks in the source domain.
        If ($gPLinks) {
            # Parse out the domain name, translate it to the destination domain name.
            # Create a distinguished name path from the SOMPath
            # wingtiptoys.local/Testing/SubTest
            ForEach ($gPLink in $gPLinks) {

                $SplitSOMPath = $gPLink.SOMPath -split '/'

                # Swap the source and destination domain names
                $DomainName = $SplitSOMPath[0]
                ForEach ($d in $MigDomains) {
                    If ($d.Source -eq $SplitSOMPath[0]) {
                        $DomainName = $d.Destination
                    }
                }
                
                # Calculate the full OU distinguished name path
                $DomainDN = 'DC=' + $DomainName.Replace('.',',DC=')
                $OU_DN = $DomainDN
                For ($i=1;$i -lt $SplitSOMPath.Length;$i++) {
                    $OU_DN = "OU=$($SplitSOMPath[$i])," + $OU_DN
                }

                # Add the DN path as a property on the object
                Add-Member -InputObject $gPLink -MemberType NoteProperty -Name gPLinkDN -Value $OU_DN

                # Now check to see that the SOM path exists in the destination domain
                # If Exists, then create the link
                # If NotExists, then report an error
                
                <#  gPLink.
                SOMName     SOMPath                           Enabled NoOverride gPLinkDN                                    
                -------     -------                           ------- ---------- --------                                    
                SubTest     wingtiptoys.local/Testing/SubTest true    false      OU=SubTest,OU=Testing,DC=cohovineyard,DC=com
                wingtiptoys wingtiptoys.local                 false   false      DC=cohovineyard,DC=com                      
                #>

                # Put the potential error line outside the context of the IF
                # so that it doesn't cause the whole construct to error out.
                # This is a bit of a hack on the error trapping,
                # but the Get-ADObject does not seem to obey the -ErrorAction parameter
                # at least with PS v2 on 2008 R2.
                $SOMPath = $null
                $ErrorActionPreference = 'SilentlyContinue'
                $SOMPath = Get-ADObject -Server $DestServer -Identity $gPLink.gPLinkDN -Properties gPLink
                $ErrorActionPreference = 'Continue'

                # Only attempt to link the policy if the destination path exists.
                If ($SOMPath) {
                    "gPLink: $($gPLink.gPLinkDN)"
                    # It is possible that the policy is already linked to the destination path.
                    try {
                        New-GPLink -Domain $DestDomain -Server $DestServer `
                            -Name $GPMBackup.GPODisplayName `
                            -Target $gPLink.gPLinkDN `
                            -LinkEnabled $(If ($gPLink.Enabled -eq 'true') {'Yes'} Else {'No'}) `
                            -Enforced $(If ($gPLink.NoOverride -eq 'true') {'Yes'} Else {'No'}) `
                            -Order $(If ($SOMPath.gPLink.Length -gt 1) {$SOMPath.gPLink.Split(']').Length} Else {1}) `
                            -ErrorAction Stop
                        # We calculated the order by counting how many gPLinks already exist.
                        # This ensures that it is always linked last in the order.
                    }
                    catch {
                        Write-Warning "gPLink Error: $($gPLink.gPLinkDN)"
                        $_.Exception
                    }
                } Else {
                    Write-Warning "gPLink path does not exist: $($gPLink.gPLinkDN)"
                } # End if SOMPath exists
            } # End ForEach gPLink
        } Else {
            "No gPLinks for GPO: $($GPMBackup.GPODisplayName)."
        } # End If gPLinks exist
    }
}


#.ExternalHelp GPOMigration.psm1-help.xml
Function Set-GPWMIFilterFromBackup {
Param (
    [Parameter(Mandatory=$true)]
    [String]
    $DestDomain,
    [Parameter(Mandatory=$true)]
    [String]
    $DestServer,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $BackupPath
)
    # Get the WMI Filter associated with each GPO backup
    $GPOBackups = Get-ChildItem $BackupPath -Filter "backup.xml" -Recurse

    ForEach ($Backup in $GPOBackups) {

        $GPODisplayName = $WMIFilterName = $null

        # XmlDocument.Load honors the BOM and the encoding declared in the file
        $BackupXML = New-Object System.Xml.XmlDocument
        $BackupXML.Load($Backup.FullName)
        $GPODisplayName = $BackupXML.GroupPolicyBackupScheme.GroupPolicyObject.GroupPolicyCoreSettings.DisplayName."#cdata-section"
        $WMIFilterName = $BackupXML.GroupPolicyBackupScheme.GroupPolicyObject.GroupPolicyCoreSettings.WMIFilterName."#cdata-section"

        If ($WMIFilterName) {
            "Linking WMI filter '$WMIFilterName' to GPO '$GPODisplayName'."
            $WMIFilter = Get-ADObject -SearchBase "CN=SOM,CN=WMIPolicy,$((Get-ADDomain -Server $DestServer).SystemsContainer)" `
                -LDAPFilter "(&(objectClass=msWMI-Som)(msWMI-Name=$WMIFilterName))" `
                -Server $DestServer
            If ($WMIFilter) {
                Set-ADObject -Identity (Get-GPO -Name $GPODisplayName -Domain $DestDomain -Server $DestServer).Path `
                    -Replace @{gPCWQLFilter="[$DestDomain;$($WMIFilter.Name);0]"} `
                    -Server $DestServer
            } Else {
                Write-Warning "WMI filter '$WMIFilterName' NOT FOUND.  Manually create and link the WMI filter."
            }
        } Else {
            "No WMI Filter for GPO '$GPODisplayName'."
        }
    }
}


#.ExternalHelp GPOMigration.psm1-help.xml
Function Start-GPOExport {
Param (
    [Parameter(Mandatory=$true)]
    [String]
    $SrceDomain,
    [Parameter(Mandatory=$true)]
    [String]
    $SrceServer,
    [Parameter(Mandatory=$true)]
    [String[]]
    $DisplayName,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $Path  # Working path to store migration tables and backups
)
    # Backup the GPOs
    # Capture the backup path for subsequent cmdlets
    # Dump the WMI filters also
    $BackupPath = Invoke-BackupGPO -SrceDomain $SrceDomain -SrceServer $SrceServer -DisplayName $DisplayName -Path $Path
    
    # Dump the permissions
    Export-GPPermission -SrceDomain $SrceDomain -SrceServer $SrceServer -DisplayName $DisplayName -Path $BackupPath

    # Dump the WMI filters
    # This is called from Invoke-BackupGPO
    #Export-WMIFilter -SrceServer $SrceServer -Path $BackupPath

    "Use this path as input for the import command."
    "BackupPath: ""$BackupPath"""
} # End Function


#.ExternalHelp GPOMigration.psm1-help.xml
Function Start-GPOImport {
Param (
    [Parameter(Mandatory=$true,HelpMessage="Must be FQDN.")]
    [ValidateScript({$_ -like "*.*"})]
    [String]
    $DestDomain,
    [Parameter(Mandatory=$true)]
    [String]
    $DestServer,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $Path,
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $BackupPath,  # Path from GPO backup
    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [String]
    $MigTableCSVPath,
    [Parameter()]
    [Switch]
    $CopyACL
)
    # Create the migration table
    # Capture the MigTablePath and MigTableCSVPath for use with subsequent cmdlets
    $MigTablePath = New-GPOMigrationTable -DestDomain $DestDomain -Path $Path -BackupPath $BackupPath -MigTableCSVPath $MigTableCSVPath

    # View the migration table
    Show-GPOMigrationTable -Path $MigTablePath

    # Validate the migration table
    # No output is good.
    Test-GPOMigrationTable -Path $MigTablePath

    # OPTIONAL
    # Remove any pre-existing GPOs of the same name in the destination environment
    # Use this for these scenarios:
    # - You want a clean import. Remove any existing policies of the same name first.
    # - You want to start over and import them again.
    # - Import-GPO will fail if a GPO of the same name exists in the target.
    Invoke-RemoveGPO -DestDomain $DestDomain -DestServer $DestServer -BackupPath $BackupPath

    # Import all from backup
    # This will fail for any policies that are missing migration table accounts in the destination domain.
    Invoke-ImportGPO -DestDomain $DestDomain -DestServer $DestServer -BackupPath $BackupPath -MigTablePath $MigTablePath -CopyACL

    # Import WMIFilters
    Import-WMIFilter -DestServer $DestServer -Path $BackupPath

    # Relink the WMI filters to the GPOs
    Set-GPWMIFilterFromBackup -DestDomain $DestDomain -DestServer $DestServer -BackupPath $BackupPath

    # Link the GPOs to destination OUs of same path
    # The migration table CSV is used to remap the domain name portion of the OU distinguished name paths.
    Import-GPLink -DestDomain $DestDomain -DestServer $DestServer -BackupPath $BackupPath -MigTableCSVPath $MigTableCSVPath
} # End Function


#.ExternalHelp GPOMigration.psm1-help.xml
Function Enable-ADSystemOnlyChange {
Param ([switch]$Disable)

    Write-Warning @'
This command must run locally on the domain controller where the
GPOs will be imported. You only need to execute this function if WMI filter
creation via script has failed. If you continue, the process will finish with
either restarting the NTDS service or rebooting the server.
'@
    If ((Read-Host "Continue? (y/n)") -ne 'y') {
        Return
    } Else {
        # Set the registry value
        $valueData = 1
        if ($Disable) {
            $valueData = 0
        }

        $key = Get-Item HKLM:\System\CurrentControlSet\Services\NTDS\Parameters -ErrorAction SilentlyContinue
        if (!$key) {
            New-Item HKLM:\System\CurrentControlSet\Services\NTDS\Parameters -ItemType RegistryKey | Out-Null
        }

        $kval = Get-ItemProperty HKLM:\System\CurrentControlSet\Services\NTDS\Parameters -Name "Allow System Only Change" -ErrorAction SilentlyContinue
        if (!$kval) {
            New-ItemProperty HKLM:\System\CurrentControlSet\Services\NTDS\Parameters -Name "Allow System Only Change" -Value $valueData -PropertyType DWORD | Out-Null
        } else {
            Set-ItemProperty HKLM:\System\CurrentControlSet\Services\NTDS\Parameters -Name "Allow System Only Change" -Value $valueData | Out-Null
        }

        # Restart the NTDS service. Use a reboot on older OS where the service does not exist.
        If (Get-Service NTDS -ErrorAction SilentlyContinue) {
            Write-Warning "You must restart the Directory Service to coninue..."
            Restart-Service NTDS -Confirm:$true
        } Else {
            Write-Warning "You must reboot the server to coninue..."
            Restart-Computer localhost -Confirm:$true
        }

    } # End If
}
