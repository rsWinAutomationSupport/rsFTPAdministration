function Get-TargetResource
{
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Username,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Password

    )

    if(!(Get-WindowsFeature -Name Web-Mgmt-Service).Installed)
    {
        Throw "Please ensure that Web-Mgmt-Service feature is installed."
    }
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Web.Management") | Out-Null
    [Microsoft.Web.Management.Server.ManagementAuthentication]::GetUser($username) -ne 0
    $returnvalue = @{
                        Username = $Username
                        Password = $Password
                        Ensure = if([Microsoft.Web.Management.Server.ManagementAuthentication]::GetUser($username) -ne 0) {"Present"} else {"Absent"}
                    }

    $returnvalue
}

function Set-TargetResource
{
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Username,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Password,

        [Parameter(Mandatory)]
        [ValidateSet("Present", "Absent")]
        [String] $Ensure
    )
    if(!(Get-WindowsFeature -Name Web-Mgmt-Service).Installed)
    {
        Throw "Please ensure that Web-Mgmt-Service feature is installed."
    }
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Web.Management") | Out-Null
    if ( $Ensure -eq "Absent" )
    {
        if( [Microsoft.Web.Management.Server.ManagementAuthentication]::GetUser($Username) -ne $null )
        {
            [Microsoft.Web.Management.Server.ManagementAuthentication]::DeleteUser($Username)
            Write-Verbose "Deleting User:$Username"
        }
    }
    else
    {
        if( [Microsoft.Web.Management.Server.ManagementAuthentication]::GetUser($Username) -eq $null )
        {
            [Microsoft.Web.Management.Server.ManagementAuthentication]::CreateUser($Username,$Password)
            Write-Verbose "Creating User:$Username"
        }
        [Microsoft.Web.Management.Server.ManagementAuthentication]::SetPassword($Username,$Password)
        Write-Verbose "Setting Password for:$Username"
    }
}

function Test-TargetResource
{
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Username,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Password,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Ensure
    )
    if(!(Get-WindowsFeature -Name Web-Mgmt-Service).Installed)
    {
        Throw "Please ensure that Web-Mgmt-Service feature is installed."
    }
    $testresult = $false

    #Changing testresult to $false to always set Passwords minimum

    $testresult
}
Export-ModuleMember -Function *-TargetResource