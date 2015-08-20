param(
[string]$K2Server = "localhost", 
[int]$K2Port = "5555",
[string]$adFilterQuery = "(&(objectCategory=User)(sAMAccountName=BulkUser.0020.*))",
[string]$ldapPath = "LDAP://DC=DENALLIX,DC=COM",
[string]$netbiosName = "DENALLIX"
)



Add-Type -AssemblyName ("SourceCode.Security.UserRoleManager.Management, Version=4.0.0.0, Culture=neutral, PublicKeyToken=16a2c5aaaa1b130d")
Add-Type -AssemblyName ("SourceCode.HostClientAPI, Version=4.0.0.0, Culture=neutral, PublicKeyToken=16a2c5aaaa1b130d")

Function GetK2ConnectionString{
	Param([string]$k2hostname, [int] $K2port = 5555)

	$constr = New-Object -TypeName SourceCode.Hosting.Client.BaseAPI.SCConnectionStringBuilder
	$constr.IsPrimaryLogin = $true
	$constr.Authenticate = $true
	$constr.Integrated = $true
	$constr.Host = $K2hostname
	$constr.Port = $K2port
	return $constr.ConnectionString
}


Function ResolveUser{
	Param($urm, $user)
	
	$swResolve = [Diagnostics.Stopwatch]::StartNew()
	Write-Debug "Resolving $user"
	
	$fqn = New-Object -TypeName SourceCode.Hosting.Server.Interfaces.FQName -ArgumentList $user
	$urm.ResolveIdentity($fqn, [SourceCode.Hosting.Server.Interfaces.IdentityType]::User, [SourceCode.Hosting.Server.Interfaces.IdentitySection]::Identity)
	Write-Debug "Resolved $user Identity in $($swResolve.ElapsedMilliseconds)ms."
	$urm.ResolveIdentity($fqn, [SourceCode.Hosting.Server.Interfaces.IdentityType]::User, [SourceCode.Hosting.Server.Interfaces.IdentitySection]::Members)
	Write-Debug "Resolved $user Members in $($swResolve.ElapsedMilliseconds)ms."
	$urm.ResolveIdentity($fqn, [SourceCode.Hosting.Server.Interfaces.IdentityType]::User, [SourceCode.Hosting.Server.Interfaces.IdentitySection]::Containers)
	Write-Debug "Resolved $user Containers in $($swResolve.ElapsedMilliseconds)ms."
	Write-Host "Resolved user $user in $($swResolve.ElapsedMilliseconds)ms."
}


$sw = [Diagnostics.Stopwatch]::StartNew()

Write-Host "Starting K2 ResolveUser script."
Write-Debug "$($sw.ElapsedMilliseconds)ms: Connecting to AD. Ldap: $ldap - Filter: $adFilterQuery"

$dirEntry = New-Object System.DirectoryServices.DirectoryEntry($ldap)
$searcher = New-Object System.DirectoryServices.DirectorySearcher($dirEntry)
	
$searcher.Filter = $adFilterQuery
$searcher.PageSize = 1000;
$searcher.SearchScope = "Subtree"
$searcher.PropertiesToLoad.Add("sAMAccountName") | Out-Null
$searcher.PropertiesToLoad.Add("objectClass") | Out-Null

Write-Debug "$($sw.ElapsedMilliseconds)ms: Starting FindAll()"
$searchResult = $searcher.FindAll()
Write-Debug "$($sw.ElapsedMilliseconds)ms: Completed FindAll."

$usersToResolve = @()

Write-Host "Reading users from AD using filter: $adFilterQuery"
foreach ($result in $searchResult) {
	$props = $result.Properties
	if ($props.objectclass.Contains("user") -eq $true) {
		$user = [string]::Concat("K2:", $netbiosName, "\", $props.samaccountname)
        $usersToResolve += $user
        Write-Debug "$($sw.ElapsedMilliseconds)ms: Adding $user to list of users to resolve."
    } else {
        Write-Debug "$($sw.ElapsedMilliseconds)ms: Skipping $($objResult.Path) - Not a User ObjectClass"
    }
}
Write-Host "Found $($usersToResolve.Count) users to resolve. Time used until now: $($sw.ElapsedMilliseconds)ms."
Write-Debug "$($sw.ElapsedMilliseconds)ms: Cleaning up AD resources..."
$searchResult.Dispose()
$searcher.Dispose()
$dirEntry.Dispose()


Write-Host "Starting user resolution loop. Time used until now: $($sw.ElapsedMilliseconds)ms."
$constr = GetK2ConnectionString -K2Hostname $K2Server -K2Port $K2Port
Write-Debug "$($sw.ElapsedMilliseconds)ms: Using K2 connection string: $constr"

$urm = New-Object SourceCode.Security.UserRoleManager.Management.UserRoleManager
$urm.CreateConnection() | Out-Null
$urm.Connection.Open($constr) | Out-Null
Write-Host "Connected to K2 server: $K2Server"

foreach ($user in $usersToResolve) {
    ResolveUser -urm $urm -user $user
}

$urm.Connection.Close();

Write-Host "K2 ResolveUser script completed in $($sw.ElapsedMilliseconds)ms."

