function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,
		[parameter(Mandatory = $true)]
		[System.String]
		$Path,
        [parameter(Mandatory = $true)]
		[System.String]
		$Ensure
	)

	if ( (Get-Website -Name $Name) -eq $null )
    {
        $returnValue = @{
		    Name = $Name
            Ensure = if($ftpsite) {"Present"} else {"Absent"}
            }
        return $returnValue
	}
    $ftpSite = Get-Website -Name $Name -ErrorAction SilentlyContinue
    $changeAccess = @()
    $readAccess = @()
    $fullAccess = @()
    $noAccess = @()
    if ($ftpSite -ne $null)
    {
        $ftpAccess = (Get-WebConfiguration -Filter /System.FtpServer/Security/Authorization -PSPath IIS: -Location $Name).Collection
        $ftpAccess | %  {
            $access = $_;
            if ($access.permissions -eq 'Write' -and $access.accessType -eq 'Allow')
            {
                $changeAccess += $access.users
            }
            elseif ($access.permissions -eq 'Read' -and $access.accessType -eq 'Allow')
            {
                $readAccess += $access.users
            }            
            elseif ($access.permissions -eq 'Read,Write' -and $access.accessType -eq 'Allow')
            {
                $fullAccess += $access.users
            }
            elseif ($access.permissions -eq 'Read,Write' -and $access.accessType -eq 'Deny')
            {
                $noAccess += $access.users
            }
        }
    }
    else
    {
        Write-Verbose "FTP with name $Name does not exist"
    } 

    $firewallSupport = Get-WebConfiguration system.ftpServer/firewallSupport
	$returnValue = @{
		Name = $ftpSite.Name
		Path = $ftpSite.physicalPath
        Binding = ($ftpSite.bindings.Collection | ? {$_protocol -eq 'ftp'}).bindinginformation
        CertHash = Get-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.serverCertHash.value
        SSLEnabled = if ( (Get-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.controlChannelPolicy.value) -eq 1) {$true} else {$false}
        ChangeAccess = $changeAccess
        ReadAccess = $readAccess
        FullAccess = $fullAccess
        NoAccess = $noAccess
        UserIsolation = if( (Get-ItemProperty IIS:\Sites\$Name -Name ftpserver.userisolation.mode.value) -eq 3 ) { $true } else { $false }
        LowPassivePort = $firewallSupport.lowDataChannelPort
        HighPassivePort = $firewallSupport.highDataChannelPort
        ExternalIp4Address = Get-WebConfigurationProperty $('/system.applicationHost/sites/site[@name ="' + $Name + '"]') -name ftpServer.firewallSupport.externalIp4Address.value -PSPath iis:\
        Ensure = if($ftpsite) {"Present"} else {"Absent"}
	}
	$returnValue
}

function Set-TargetResource
{
	[CmdletBinding()]
    Param
    (           
        [parameter(Mandatory = $true)]
		[System.String]
		$Name,

        [parameter(Mandatory = $true)]
		[System.String]
		$Path,

		[System.String[]]
		$Binding = @(":21:"),

        [ValidateSet("Started","Stopped")]
		[System.String]
        $State = "Started",

        [System.Boolean]
        $SSLEnabled = $false,

        [System.Boolean]
        $UserIsolation = $false,

        [System.String]
        $CertHash = "",
        
        [System.String]
        $LowPassivePort = "0",

        [System.String]
        $HighPassivePort = "0",

        [System.String]
        $ExternalIp4Address = "",

        [System.String[]]
        $FullAccess = @(),

        [System.String[]]
        $ChangeAccess = @(),

        [System.String[]]
        $ReadAccess = @(),

        [System.String[]]
        $NoAccess = @(),

        [parameter(Mandatory = $true)]
		[System.String]
		$Ensure
    )
    $features = @("Web-Ftp-Server","Web-Mgmt-Service","Web-Ftp-Ext")
    foreach ( $feature in $features )
    {
        if(!(Get-WindowsFeature -Name $feature).Installed){
            Throw "Please ensure $feature is Installed"
        }
    }
    if ( $Ensure -eq "Absent" -and ((Get-Website $Name) -ne $null) )
    {
        Remove-Item IIS:\Sites\$Name -Recurse
        Write-Verbose "Removing Site $Name"
    }
    else
    {
        # IIS Permissions
        $ErrorActionPreference = "SilentlyContinue"
        ICACLS --% "%SystemDrive%\Windows\System32\inetsrv\config" /Grant "Network Service":R /T
        $ErrorActionPreference = "Continue"
        ICACLS --% "%SystemDrive%\Windows\System32\inetsrv\config\administration.config" /Grant "Network Service":R
        ICACLS --% "%SystemDrive%\Windows\System32\inetsrv\config\redirection.config" /Grant "Network Service":R
        
        if(!(Test-Path "$Path")){New-Item $Path -itemType directory;Write-Verbose "Create FTP Directory"}

        # Create FTP Site
        if( (Get-Website $Name) -eq $null ) {New-Item IIS:\Sites\$Name -Bindings ( $binding | % {"@{protocol=ftp;bindingInformation=$_}"} ) -PhysicalPath $Path -Verbose:$false | Out-Null;Write-Verbose "Creating Site $Name"}
        elseif ( (Get-Website $Name).count -gt 1) { Throw "Cannot handle Sites named the same"}
        if((Compare-Object $binding (Get-Website $Name).bindings.Collection.bindingInformation).InputObject.count -ne 0 ) 
        {
            Set-ItemProperty IIS:\Sites\$Name –name Bindings –value ( $binding | % {@{protocol="ftp";bindingInformation=$_}} )
            Write-Verbose "Set Bindings on site $Name"
        }
        # Set SSL
        if($SSLEnabled -eq $true)
        {
            Set-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.controlChannelPolicy -Value 1
            Set-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.dataChannelPolicy -Value 1
            Set-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.ssl128 -Value $true
            Write-Verbose "Set SSL to True on $Name"
        }
        else
        {
            Set-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
            Set-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.dataChannelPolicy -Value 0
            Set-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.ssl128 -Value $false
            Write-Verbose "Set SSL to False on $Name"
        }
        Set-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.serverCertHash -Value $CertHash
        Write-Verbose "Setting SSL to $CertHash"
        #Passive Port Range
        $firewallSupport = Get-WebConfiguration system.ftpServer/firewallSupport
        if ( $firewallSupport.lowDataChannelPort -ne $LowPassivePort -or $firewallSupport.highDataChannelPort -ne $highPassivePort ) 
        {
            $firewallSupport.lowDataChannelPort = $LowPassivePort
            $firewallSupport.highDataChannelPort = $HighPassivePort
            $firewallSupport | Set-WebConfiguration system.ftpServer/firewallSupport
            Write-Verbose "Set Passive Porta Range to $LowPassivePort-$HighPassivePort"
            Write-Verbose "Stopping FTPSVC"
            Stop-Service FTPSVC
            Write-Verbose "Starting FTPSVC"
            Start-Service FTPSVC
        }
        # External IPv4 Address
        if ( (Get-WebConfigurationProperty $('/system.applicationHost/sites/site[@name ="' + $Name + '"]') -name ftpServer.firewallSupport.externalIp4Address.value -PSPath iis:\) -ne $ExternalIp4Address)
        {
            Set-WebConfigurationProperty $('/system.applicationHost/sites/site[@name ="' + $Name + '"]') -name ftpServer.firewallSupport.externalIp4Address -PSPath iis:\ -Value $ExternalIp4Address
        }
        # Add User Isolation
        if ( $UserIsolation -eq $true)
        {
            if ( (Get-ItemProperty IIS:\Sites\$Name -Name ftpserver.userisolation.mode.value) -ne 3 )
            {
                Set-ItemProperty IIS:\Sites\$Name -Name ftpserver.userisolation.mode -Value 3
                Write-Verbose "Setting UserIsolation to User Home Directory without Global Virtual Directories"
            }
        }
        else
        {
            Set-ItemProperty IIS:\Sites\$Name -Name ftpserver.userisolation.mode -Value 4
            Write-Verbose "Setting UserIsolation to FTP Root Directory"
        }
        # Add IIS Manager User to Site Level
        $allUsers = @()
        $allUsers = $FullAccess + $NoAccess + $ReadAccess + $ChangeAccess | Sort-Object -Unique
        [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Web.Management") | Out-Null      
        foreach ($user in ([Microsoft.Web.Management.Server.ManagementAuthorization]::GetAuthorizedUsers($Name,$True,0,1000).name) )
        {
                [Microsoft.Web.Management.Server.ManagementAuthorization]::Revoke($user, $Name)
                Write-Verbose "Removing $user from IISAuth on Site $Name"
        }
        if ( $allUsers -ne $null )
        {
            foreach ( $user in $allUsers )
            {
                if ( ([Microsoft.Web.Management.Server.ManagementAuthorization]::GetAuthorizedUsers($Name,$True,0,1000).name -notcontains $user ) )
                {
                    [Microsoft.Web.Management.Server.ManagementAuthorization]::Grant($user, $Name, $False)
                    Write-Verbose "Adding $user to IISAuth on Site $Name"
                }
                if( $UserIsolation -eq $true -and !(Test-Path "$Path\LocalUser\$user")){New-Item "$Path\LocalUser\$user" -itemType directory;Write-Verbose "Create Isolated FTP directory for $user"}
            }
        }
        # Set IISAuth to Enabled
        Set-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $false
        $IISAuth = (Get-WebConfigurationProperty $('/system.applicationHost/sites/site[@name ="' + $Name + '"]') -name ftpServer.security.authentication.customAuthentication.providers -PSPath iis:\).Collection
        if( $IISAuth.Name -ne "IisManagerAuth" -or $IISAuth.enabled -ne "True" )
        {
            Set-WebconfigurationProperty $('/system.applicationHost/sites/site[@name ="' + $Name + '"]') -name ftpServer.security.authentication.customAuthentication.providers -value @{name='IisManagerAuth';enabled='true'} -PSPath iis:\
            Write-Verbose "Setting IISAuthentication to Enabled"
        }        

        # Set IIS Manager User(s) to Site Level
        Clear-Webconfiguration '/system.ftpServer/security/authorization' -PSPath IIS: -Location $Name
        Write-Verbose "Clearing FTP Authorization"
        if ( $FullAccess -ne $null )
        {
            foreach ( $user in $FullAccess )
            {
                Add-WebConfiguration -Filter /System.FtpServer/Security/Authorization -Value (@{AccessType="Allow"; Users="$user"; Permissions="Read,Write"}) -PSPath IIS: -Location $Name
                Write-Verbose "Adding $user with Full FTP Access"
            }
        }
        if ( $ChangeAccess -ne $null )
        {
            foreach ( $user in $ChangeAccess )
            {
                Add-WebConfiguration -Filter /System.FtpServer/Security/Authorization -Value (@{AccessType="Allow"; Users="$user"; Permissions="Write"}) -PSPath IIS: -Location $Name
                Write-Verbose "Adding $user with Change FTP Access"
            }
        }
        if ( $ReadAccess -ne $null )
        {
            foreach ( $user in $ReadAccess )
            {
                Add-WebConfiguration -Filter /System.FtpServer/Security/Authorization -Value (@{AccessType="Allow"; Users="$user"; Permissions="Read"}) -PSPath IIS: -Location $Name
                Write-Verbose "Adding $user with Read FTP Access"
            }
        }
        if ( $NoAccess -ne $null )
        {
            foreach ( $user in $NoAccess )
            {
                Add-WebConfiguration -Filter /System.FtpServer/Security/Authorization -Value (@{AccessType="Deny"; Users="$user"; Permissions="Read,Write"}) -PSPath IIS: -Location $Name
                Write-Verbose "Adding $user with Deny FTP Access"
            }
        }
        ICACLS $Path --% /Grant "Network Service":M /T
        Write-Verbose "Set FTP Permissions on FTP Folder $Path"

    }
}

function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
    Param
    (           
        [parameter(Mandatory = $true)]
		[System.String]
		$Name,

        [parameter(Mandatory = $true)]
		[System.String]
		$Path,

		[System.String[]]
		$Binding = @(":21:"),

        [ValidateSet("Started","Stopped")]
		[System.String]
        $State = "Started",

        [System.Boolean]
        $SSLEnabled = $false,

        [System.Boolean]
        $UserIsolation = $false,

        [System.String]
        $CertHash = "",

        [System.String]
        $LowPassivePort = "0",

        [System.String]
        $HighPassivePort = "0",

        [System.String]
        $ExternalIp4Address = "",

        [System.String[]]
        $FullAccess = @(""),

        [System.String[]]
        $ChangeAccess = @(""),

        [System.String[]]
        $ReadAccess = @(""),

        [System.String[]]
        $NoAccess = @(""),

        [parameter(Mandatory = $true)]
		[System.String]
		$Ensure
    )
    $testResult = $true;

    $features = @("Web-Ftp-Server","Web-Mgmt-Service","Web-Ftp-Ext")
    foreach ( $feature in $features )
    {
        if(!(Get-WindowsFeature -Name $feature).Installed){
            Throw "Please ensure $feature is Installed"
        }
    }
    if ( $Ensure -eq "Absent" -and ((Get-Website $Name) -ne $null) ){  Write-Verbose "Site Needs to be Removed"; return $false}
    if ( $Ensure -eq "Absent" -and ((Get-Website $Name) -eq $null) ){  Write-Verbose "Nothing to be Done"; return $true}
    if ( $Ensure -eq "Present" -and ((Get-Website $Name) -eq $null) ){ Write-Verbose "Site Does not Exist"; return $false }
    if(!(Test-Path $Path)){Write-Verbose "FTP Directory $Path does not exist"; return $false}
    if((Compare-Object $Binding (Get-Website $Name).bindings.Collection.bindingInformation).InputObject.count -ne 0 ) {$testresult = $false; Write-Verbose "Bindings are incorrect"}
    if(!(Test-Path $Path)){$testresult = $false; Write-Verbose "Create FTP Directory"}
    if(!((get-acl $Path).Access.IdentityReference -eq "NT AUTHORITY\NETWORK SERVICE" -and (get-acl $Path).Access.FileSystemRights -eq "Modify, Synchronize"))
    {
        $testresult = $false
        Write-Verbose "Change Permissions"
    }
    if($SSLEnabled -eq $true)
    {
        if ((Get-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.controlChannelPolicy.value) -ne 1 ) { $testresult = $false; Write-Verbose "SSL needs to be enabled" }
        if ((Get-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.dataChannelPolicy.value) -ne 1 ) { $testresult = $false; Write-Verbose "SSL needs to be enabled" }
    }
    else
    {
        if ((Get-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.controlChannelPolicy.value) -ne 0 ) { $testresult = $false; Write-Verbose "SSL needs to be disabled" }
        if ((Get-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.dataChannelPolicy.value) -ne 0 ) { $testresult = $false; Write-Verbose "SSL needs to be disabled" }
    }
    if($CertHash -ne (Get-ItemProperty IIS:\Sites\$Name -Name ftpServer.security.ssl.serverCertHash.value) ){ $testresult = $false; Write-Verbose "SSL Certificate needs to be added/changed" }
    
    $firewallSupport = Get-WebConfiguration system.ftpServer/firewallSupport
    if ( $firewallSupport.lowDataChannelPort -ne $LowPassivePort ) { $testresult = $false; Write-Verbose "Need to Set Lower Passive Port Range"}
    if ( $firewallSupport.highDataChannelPort -ne $HighPassivePort ) { $testresult = $false; Write-Verbose "Need to Set Higher Passive Port Range"}
    $IISAuth = (Get-WebconfigurationProperty $('/system.applicationHost/sites/site[@name ="' + $Name + '"]') -name ftpServer.security.authentication.customAuthentication.providers -PSPath iis:\).collection
    if ( (Get-WebConfigurationProperty $('/system.applicationHost/sites/site[@name ="' + $Name + '"]') -name ftpServer.firewallSupport.externalIp4Address.value -PSPath iis:\) -ne $ExternalIp4Address)
    { $testresult = $false; Write-Verbose "Need to Set External IPv4 Address" }
    if ( $IISAuth.Name -ne "IisManagerAuth" -or $IISAuth.Enabled -ne $true) {$testresult = $false;Write-Verbose "IISAuth needs to be enabled"}
    $change = @()
    $read = @()
    $full = @()
    $no = @()
    $ftpAccess = (Get-WebConfiguration -Filter /System.FtpServer/Security/Authorization -PSPath IIS: -Location $Name).Collection
    $ftpAccess | %  {
        $access = $_;
        if ($access.permissions -eq 'Write' -and $access.accessType -eq 'Allow')
        {
            $change += $access.users
        }
        elseif ($access.permissions -eq 'Read' -and $access.accessType -eq 'Allow')
        {
            $read += $access.users
        }            
        elseif ($access.permissions -eq 'Read,Write' -and $access.accessType -eq 'Allow')
        {
            $full += $access.users
        }
        elseif ($access.permissions -eq 'Read,Write' -and $access.accessType -eq 'Deny')
        {
            $no += $access.users
        }
    }
    if ( $noAccess -ne $null ) { if ( (Compare-Object $no $noAccess).InputObject.count -ne 0 ) {$testresult = $false; Write-Verbose "No Access List Different"} }
    if ( $readAccess -ne $null ) { if ( (Compare-Object $read $readAccess).InputObject.count -ne 0 ) {$testresult = $false; Write-Verbose "Read Access List Different"} }
    if ( $fullAccess -ne $null ) { if ( (Compare-Object $full $FullAccess).InputObject.count -ne 0 ) {$testresult = $false; Write-Verbose "Full Access List Different"} }
    if ( $changeAccess -ne $null ) { if ( (Compare-Object $change $changeAccess).InputObject.count -ne 0 ) {$testresult = $false; Write-Verbose "Change Access List Different"} }
    $allUsers = @()
    $allUsers = $FullAccess + $NoAccess + $ReadAccess + $ChangeAccess | ? { $_ } | Sort-Object -Unique
    if ( $UserIsolation -eq $true -and (Get-ItemProperty IIS:\Sites\$Name -Name ftpserver.userisolation.mode.value) -ne 3){$testresult = $false; Write-Verbose "Need to enable User Isolation"}
    if ( $UserIsolation -eq $false -and (Get-ItemProperty IIS:\Sites\$Name -Name ftpserver.userisolation.mode.value) -ne 4){$testresult = $false; Write-Verbose "Need to disable User Isolation"}
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Web.Management") | Out-Null      
    $all = ([Microsoft.Web.Management.Server.ManagementAuthorization]::GetAuthorizedUsers($Name,$True,0,1000).name)
    if ( $all -eq $null -and $allUsers -eq $null) {return $testresult }
    elseif ( $all -eq $null -and $allUsers -ne $null) {Write-Verbose "IISAuth User List Different"; return $false }
    elseif ( $all -ne $null -and $allUsers -eq $null) {Write-Verbose "IISAuth User List Different"; return $false }
    else
    {
        if ( (Compare-Object $all $allUsers).InputObject.count -ne 0 ) {$testresult = $false; Write-Verbose "IISAuth User List Different"}
    }
	$testResult
}

Export-ModuleMember -Function *-TargetResource