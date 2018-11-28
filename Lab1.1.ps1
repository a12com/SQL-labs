<# Lab 1 
Create all-in-one PS script, that:
o	installs Named instance, 
o	set up firewall rules, that is needed for access to SQL and RDP, 
o	Script returns name of installed SQL instance, and VM name in human readable view
o	Script returns list of installed SQL features in any human readable format
o	Script returns Firewall state and settings, that were changed by Student. 
#>

Param
	(
	# address of SQL server and path to setup ini file
	[string]$SqlSrvr = "lon-svr1",
	[string]$SqlIniFile="C:\Training\M4 SQL\Topic1\ConfigurationFile.ini"
	)
Begin
	{
	# exitcode function
	function ExitWith-Code 
		{
		param 
		(
		[int]$ExitCode,
		[string]$lastErr=$Error[0]
		)

		$exception=$NULL
		$innerException=$NULL

		# get Current Exception Value
		If ($lastErr.Exception -ne $NULL)
			{
			$exception=$LastErr.exception
			$exception | Tee-Object -FilePath $LogFilePath -Append | Write-Error
			}

		# Check if there is a more exacting Error code in Inner Exception
		If ($lastErr.exception.InnerException -ne $NULL)
			{
			$innerException=$LastErr.Exception.InnerException
			$innerException | Tee-Object -FilePath $LogFilePath -Append | Write-Error
			}

		# If No InnerException or Exception has been identified
		# Use GetBaseException Method to retrieve object
		if ($Exceptioneption-eq '' -and $InnerException -eq '')
			{
			$Exception=$LastErr.GetBaseException()
			$exception | Tee-Object -FilePath $LogFilePath -Append | Write-Error
			}

		("Script sent exitcode ({0})" -f $ExitCode ) | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Red 
		$host.SetShouldExit($ExitCode)
		exit $ExitCode
		}

	# get installed .Net version function
	function Get-DotNetFrameworkVersion
		{
		Param
		(
		[string]$ComputerName = $env:COMPUTERNAME
		)
		[string]$dotNetRegistry  = 'SOFTWARE\Microsoft\NET Framework Setup\NDP'
		[string]$dotNet4Registry = 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
		$dotNet4Builds = @{
						'30319'  = @{ Version = [string]'4.0'                                                     }
						'378389' = @{ Version = [string]'4.5'                                                     }
						'378675' = @{ Version = [string]'4.5.1'   ; Comment = '(8.1/2012R2)'                      }
						'378758' = @{ Version = [string]'4.5.1'   ; Comment = '(8/7 SP1/Vista SP2)'               }
						'379893' = @{ Version = [string]'4.5.2'                                                   }
						'380042' = @{ Version = [string]'4.5'     ; Comment = 'and later with KB3168275 rollup'   }
						'393295' = @{ Version = [string]'4.6'     ; Comment = '(Windows 10)'                      }
						'393297' = @{ Version = [string]'4.6'     ; Comment = '(NON Windows 10)'                  }
						'394254' = @{ Version = [string]'4.6.1'   ; Comment = '(Windows 10)'                      }
						'394271' = @{ Version = [string]'4.6.1'   ; Comment = '(NON Windows 10)'                  }
						'394802' = @{ Version = [string]'4.6.2'   ; Comment = '(Windows 10 1607)'                 }
						'394806' = @{ Version = [string]'4.6.2'   ; Comment = '(NON Windows 10)'                  }
						'460798' = @{ Version = [string]'4.7'     ; Comment = '(Windows 10 1703)'                 }
						'460805' = @{ Version = [string]'4.7'     ; Comment = '(NON Windows 10)'                  }
						'461308' = @{ Version = [string]'4.7.1'   ; Comment = '(Windows 10 1709)'                 }
						'461310' = @{ Version = [string]'4.7.1'   ; Comment = '(NON Windows 10)'                  }
						'461808' = @{ Version = [string]'4.7.2'   ; Comment = '(Windows 10 1803)'                 }
						'461814' = @{ Version = [string]'4.7.2'   ; Comment = '(NON Windows 10)'                  }
						}
		if($regKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $ComputerName))
			{
			if ($netRegKey = $regKey.OpenSubKey("$dotNetRegistry"))
				{
				foreach ($versionKeyName in $netRegKey.GetSubKeyNames())
					{
					if ($versionKeyName -match '^v[123]') 
						{
						$versionKey = $netRegKey.OpenSubKey($versionKeyName)
						$version = [string]($versionKey.GetValue('Version', ''))
						New-Object -TypeName PSObject -Property ([ordered]@{
								ComputerName = $computer
								Build = $version.Build
								Version = $version
								Comment = ''})
						}
					}
				}

			if ($net4RegKey = $regKey.OpenSubKey("$dotNet4Registry"))
				{
				if(-not ($net4Release = $net4RegKey.GetValue('Release')))
					{
					$net4Release = 30319
					}
				New-Object -TypeName PSObject -Property ([ordered]@{
						ComputerName = $Computer
						Build = $net4Release
						Version = $dotNet4Builds["$net4Release"].Version
						Comment = $dotNet4Builds["$net4Release"].Comment})
				}
			}

		}
	# import module to work with SQL
	Import-Module SqlServer

	# create credentials
	[string]$DomainName = "Adatum"
	$SrvrCred = Get-Credential ("{0}\Administrator" -f $DomainName)

	#region begin log file
	# create log file and put start time there
	[string]$LogFilePath = (".\lab1.1({0}).log" -f (Get-Date -Uformat %r | foreach {$_ -replace ":","."}) )
	$null | Out-File -FilePath $LogFilePath
	Write-Host ("Script log created in file {0}" -f $LogFilePath)
	[string]$Time = ("Started script at {0}" -f (Get-Date) )
	$Time | Out-File -FilePath $LogFilePath
	#endregion

	#region begin create pssession with remote server
	# create pssession to work with server
	try 
		{
		$PSS = $Null
		$PssOption = New-PSSessionOption -OpenTimeout 30 -CancelTimeout 30 -OperationTimeout 30
		$PSS = New-PSSession -ComputerName $SqlSrvr -Credential $SrvrCred -SessionOption $PssOption
		}
	catch 
		{
		("[ERROR] Could not connect to {0}" -f $SqlSrvr) | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Red 
		ExitWith-Code -ExitCode 4
		}
	#endregion
	
	#region begin check .Net version on remote server
	# run fucntion to check if host have .Net 3.5 installed
	
	("Checking installed .Net version on ({0}) ..." -f $SqlSrvr ) | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Blue 
	$RequiredDotNet = (Invoke-Command -Session $PSS -ScriptBlock ${Function:Get-DotNetFrameworkVersion}).version | where {$_ -like "3.5.*"}

	if ($RequiredDotNet -eq $false)
		{
		(".Net 3.5 is absent on server. Starting installation..." ) | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Yellow 
		
		#install .NET 3.5
		try
			{
			Invoke-Command -Session $PSS -ScriptBlock {Install-WindowsFeature Net-Framework-Core -source \\network\share\sxs}
			}
		catch 
			{
			("[ERROR] Error while installing .Net on {0}" -f $SqlSrvr) | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Red 
				ExitWith-Code -ExitCode 35
			}
		}
	else 
		{
		(".Net 3.5 is installed") | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Blue 
		}
	#endregion
	}
Process
	{
	# copy configuration file to SQL server
	Copy-Item $SqlIniFile -Destination "c:\" -ToSession $PSS
	# run installation
	Invoke-Command -Session $PSS -ScriptBlock {& d:\setup.exe /ConfigurationFile='c:\ConfigurationFile.ini' }

	#region begin configure network properties in PSSession
	# get SQL Server Instance Path:
	Enter-PSSession -Session $PSS

	$ini = get-content -Path 'c:\ConfigurationFile.ini'
	foreach ($str in $ini)
		{
		if ($str -match "INSTANCENAME=")
			{
			[string]$SqlInstanceName=($str.Split('"'))[1]
			}
		}
	[string]$SqlService = ("SQL Server ({0})" -f $SqlInstanceName)
	[string]$SqlInstancePath = ""
	[string]$SqlServiceName = ((Get-Service | WHERE { $_.DisplayName -eq $SqLService }).Name).Trim();
	If ($SQLServiceName.contains("`$")) 
		{
		[string]$SqlServiceName = $SqlServiceName.SubString($SqlServiceName.IndexOf("`$")+1,$SqlServiceName.Length-$SqlServiceName.IndexOf("`$")-1)
		}
	foreach ($i in (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server").InstalledInstances)
		{
		If ( ((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$i).contains($SqlServiceName) ) 
			{ 
			$SqlInstancePath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\"+  (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$i
			}
		} 
	[string]$SqlTcpPath = "$SqlInstancePath\MSSQLServer\SuperSocketNetLib\Tcp"

	# set SQL server IP protocol's properties:
	$IpProtocol="IPALL"   # Options: "IPALL"/"IP4"/"IP6"/Etc
	#$Enabled = "0"            # Options: "0" - Disabled / "1" - Enabled
	#$Active = "0"              # Options: "0" - Inactive / "1" - Active
	$Port = "1433"                   # Options: "0"/"" (Empty)
	$DynamicPort = ""    # Options: "0"/"" (Empty)
	#$IPAddress="::0"        # There must not be IP Address duplication for any IP Protocol

	#Set-ItemProperty -Path "$SqlTcpPath\$IPProtocol" -Name "Enabled" -Value $Enabled
	#Set-ItemProperty -Path "$SqlTcpPath\$IPProtocol" -Name "Active" -Value $Active
	Set-ItemProperty -Path "$SqlTcpPath\$IpProtocol" -Name "TcpPort" -Value $Port
	Set-ItemProperty -Path "$SqlTcpPath\$IpProtocol" -Name "TcpDynamicPorts" -Value $DynamicPort
	#Set-ItemProperty -Path "$SQLTcpPath\$IPProtocol" -Name "IPAddress" -Value $IPAddress

	# restart server to apply changes
	Restart-Service -displayname ("SQL Server ({0}})" -f $SqlInstanceName)
	
	# open windows firewall port for inbound traffic
	Import-Module NetSecurity
	New-NetFirewallRule -DisplayName "SQL 1433 allow" -Direction Inbound -Protocol Tcp -LocalPort 1433 -Action Allow
	Exit-PSSession
	#endregion
	}
End
	{
	# write down SQL instance name
	$ini = get-content $SqlIniFile
	foreach ($str in $ini)
		{
		if ($str -match "INSTANCENAME=")
			{
			[string]$SqlInstanceName=($str.Split('"'))[1]
			}
		}
	Write-Host ("Succesfully installed MSSQL on {0}. Instance name is {1}." -f $SqlSrvr, $SqlInstanceName)	
	
	# check firewall status on remote server
	$Compliance = "Firewall Not Enabled"
	$Check = Invoke-Command -Session $PSS -ScriptBlock {Get-Netfirewallprofile | Where-Object {$_.Name -eq 'Domain' -and $_.Enabled -eq 'True'} }
	$Check = Invoke-Command -Session $PSS -ScriptBlock {Get-Netfirewallprofile | Where-Object {$_.Name -eq 'Public' -and $_.Enabled -eq 'True'} }
	$Check = Invoke-Command -Session $PSS -ScriptBlock {Get-Netfirewallprofile | Where-Object {$_.Name -eq 'Private' -and $_.Enabled -eq 'True'} }
	if ($Check) 
		{
		$Compliance = 'Firewall Enabled'
		}
	$Compliance
	$GetFirewallRule = Invoke-Command -Session $PSS -ScriptBlock {Get-NetFirewallRule -DisplayName "SQL 1433 allow"}

	#SQL Features list
	$SqlFeaturesList = Invoke-Command -Session $PSS -ScriptBlock {get-wmiobject win32_product | Where {$_.Name -match "SQL" -AND $_.vendor -eq "Microsoft Corporation"} | Select name, version}

	}


