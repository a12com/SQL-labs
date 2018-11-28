<# ExitLab
Create PS script that:
* install named instance of MSSQL
* set up fixed TCP port 1467
* restore 2 DB's based on AdventureWorks
* set recovery model simple for 1st and full for 2nd
* encrypt 1st DB
* add 3 win users:
     - 1 for sysadmin server role
     - 1 for Server Agent with diskadmin server role & db_backupoperator on all DB's
     - 1 user with db_dataread on user DB's
* create 

Prerequisites:
* ready to go configuration file on local computer
* adventureworks2012 Db files on local computer
* remote DC server
* remote server for SQL with disks separate phisical disks E,F,H for data, log and backup files
#>

Param
    (
    # address of SQL server and path to setup ini file
    [string]$DcSrvr = "lon-dc1",
    [string]$SqlSrvrAddress = "lon-svr2",
    [string]$SqlIniFile="C:\Training\M4 SQL\Topic1\ConfigurationFile.ini",
    [int]$SqlSrvrPort = 1467
    )

Begin
    {
	# import module to work with SQL
	Import-Module SqlServer
    
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

		("Script sent exitcode ({0})" -f $ExitCode ) | Write-Error 
		#$host.SetShouldExit($ExitCode)
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
    
    # SQL query function (invoke-sqlcmd)
    Function Run-SqlQry 
        {
        Param
        (
        [string]$Query,
        [string]$SrvrIns=$SqlSrvrConnStr,
        $Credential=$SqlCred
        )
        Try
            {
            Invoke-SqlCmd -ServerInstance $SrvrIns -Credential $Credential -Query $Query -QueryTimeout 0 -ErrorAction Stop
            Start-Sleep -Milliseconds 1500
            }
        Catch
            {
            ExitWith-Code -exitCode 10
            }
        }

    #region begin create credentials and SQL server connection address string

    # parse config file for instance name and SA password
    $ini = get-content -Path $SqlIniFile
	foreach ($str in $ini)
		{
		if ($str -match "INSTANCENAME=")
			{
			[string]$SqlInstanceName=($str.Split('"'))[1]
            }
        elseif ($str -match "SAPWD=") 
            {
            [string]$SqlPwdNS=($str.Split('"'))[1]
            }
        }
    [string]$SqlSrvrConnStr = ("{0}\{1},{2}" -f $SqlSrvrAddress, $SqlInstanceName, $SqlSrvrPort)
    
    # create credentials
    [System.Security.SecureString]$SqlPwd = ConvertTo-SecureString $SqlPwdNS -AsPlainText -Force
    [string]$SqlUsrName = "SA"
    Write-Output ("Enter {0} password" -f $SqlUsrName)
    [string]$DomainName = "Adatum"
    $DcCred = Get-Credential ("{0}\Administrator" -f $DomainName)    
    $SqlCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $SqlUsrName, $SqlPwd
    #endregion

    #region begin create PSsessions to DC and SQL servers
    # create pssession to work with DC server
    try 
        {
        $PssSql = $PssDc = $Null
        $PssOption = New-PSSessionOption -OpenTimeout 30 -CancelTimeout 30 -OperationTimeout 30
        $PssSql = New-PSSession -ComputerName $SqlSrvrAddress -Credential $DcCred -SessionOption $PssOption
        $PssDC = New-PSSession -ComputerName $SqlSrvrAddress -Credential $DcCred -SessionOption $PssOption
        }
    catch 
        {
        ("[ERROR] Could not connect to server") |  Write-Error
        ExitWith-Code -ExitCode 4
        }
    #endregion
    
    #region begin get user list
    # get userlist
    try
        {
        $UserList = Import-Csv '.\usrlst.csv'
        }
    catch
        {
        "[ERROR] User list not found" | Write-Error
        ExitWithCode -exitcode 12
        }
    #endregion

    }

Process
    {
    #region begin create users on DC
    # create users on DC
    foreach ($User in $UserList)
        {
        $UserPwd = $null
        $UserPwd = ConvertTo-SecureString $User.Password -AsPlainText -Force
        try 
            {
            New-ADUser -Name $User.Username -AccountPassword $UserPwd -Description ("SQL Server {0}" -f$User.Function) -Enabled 1 -Server $DcSrvr -Credential $DcCred
            ( "User {0} successfully created on DC {1}" -f $User.username, $DcSrvr) | Write-Host -ForegroundColor Blue
            }
        catch 
            {
            ( "[ERROR] Could not create user {0} on {1}" -f $User.Username, $DcSrvr ) | Write-Host -ForegroundColor Red
            }        
        }
    #endregion
    
    #region begin check .Net version on remote server
	# run fucntion to check if host have .Net 3.5 installed
    ("Checking existence of .NET 3.5..." ) | Write-Host -ForegroundColor Blue 
	$RequiredDotNet = (Invoke-Command -Session $PssSql -ScriptBlock ${Function:Get-DotNetFrameworkVersion}).version | where {$_ -like "3.5.*"}
    
	if ($RequiredDotNet -eq $false)
		{
		(".Net 3.5 is absent on server. Starting installation..." ) | Write-Host -ForegroundColor Yellow 
		
		#install .NET 3.5
		try
			{
			Invoke-Command -Session $PssSql -ScriptBlock {Install-WindowsFeature Net-Framework-Core -source \\network\share\sxs}
			}
		catch 
			{
			("[ERROR] Error while installing .Net on {0}" -f $SqlSrvr) | Write-Host -ForegroundColor Red 
				ExitWith-Code -ExitCode 35
			}
		}
	else 
		{
		("OK") | Write-Host -ForegroundColor Blue 
		}
	#endregion
    
    #region begin install MSSQL server
    # copy configuration file to SQL server
    try 
        {
        Copy-Item $SqlIniFile -Destination "c:\" -ToSession $PssSql
        }
    catch 
        {
        ("[ERROR] Could not copy config file to destination server ({0})" -f $SqlSrvrAddress) | Write-Error
        ExitWithCode -exitcode 8
        }

    # run installation
    try 
        {
        Invoke-Command -Session $PssSql -ScriptBlock {& d:\setup.exe /ConfigurationFile='c:\ConfigurationFile.ini' }
        }
    catch 
        {
        ("[ERROR] Could not install server ({0})" -f $SqlSrvrAddress) | Write-Error
        ExitWithCode -exitcode 8
        }
    #endregion
    
    #region begin configure network properties in PSSession

	Enter-PSSession -Session $PssSql
    
    # get instance name from config file
	$ini = get-content -Path 'c:\ConfigurationFile.ini'
	foreach ($str in $ini)
		{
		if ($str -match "INSTANCENAME=")
			{
			[string]$SqlInstanceName=($str.Split('"'))[1]
			}
        }
    # get SQL Server Instance Path:
	[string]$SqlService = ("SQL Server ({0})" -f $SqlInstanceName)
	[string]$SqlInstancePath = ""
	[string]$SqlServiceName = ((Get-Service | Where-Object { $_.DisplayName -eq $SqlService }).Name).Trim()
	If ($SQLServiceName.contains("`$")) 
		{
		[string]$SqlServiceName = $SqlServiceName.SubString($SqlServiceName.IndexOf("`$")+1,$SqlServiceName.Length-$SqlServiceName.IndexOf("`$")-1)
		}
	foreach ($i in (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server").InstalledInstances)
		{
		If ( ((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$i).contains($SqlInstanceName) ) 
			{ 
			$SqlInstancePath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\"+  (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL").$i
			}
		} 
    [string]$SqlTcpPath = "$SqlInstancePath\MSSQLServer\SuperSocketNetLib\Tcp"
 
	# set SQL server IP protocol's properties:
	$IpProtocol="IPALL"   # Options: "IPALL"/"IP4"/"IP6"/Etc
	#$Enabled = "0"            # Options: "0" - Disabled / "1" - Enabled
	#$Active = "0"              # Options: "0" - Inactive / "1" - Active
	$Port = "1467"                   # Options: "0"/"" (Empty)
	$DynamicPort = ""    # Options: "0"/"" (Empty)
	#$IPAddress="::0"        # There must not be IP Address duplication for any IP Protocol

	#Set-ItemProperty -Path "$SqlTcpPath\$IPProtocol" -Name "Enabled" -Value $Enabled
	#Set-ItemProperty -Path "$SqlTcpPath\$IPProtocol" -Name "Active" -Value $Active
	Set-ItemProperty -Path "$SqlTcpPath\$IpProtocol" -Name "TcpPort" -Value $Port
	Set-ItemProperty -Path "$SqlTcpPath\$IpProtocol" -Name "TcpDynamicPorts" -Value $DynamicPort
	#Set-ItemProperty -Path "$SQLTcpPath\$IPProtocol" -Name "IPAddress" -Value $IPAddress

	# restart server to apply changes
	Restart-Service -displayname ("SQL Server ({0})" -f $SqlInstanceName) -Force
	
	# open windows firewall port for inbound traffic
	Import-Module NetSecurity
	New-NetFirewallRule -DisplayName "SQL 1467 allow" -Direction Inbound -Protocol Tcp -LocalPort 1467 -Action Allow
	Exit-PSSession
    #endregion
    
    #region begin create SQL queries to run

    # query to assign logins on SQL server
    [string]$CreateSqlLogins = @"
            -- Create ExitLabSqlAdmin login
            USE [master]
            GO
            CREATE LOGIN [ADATUM\ExitLabSqlAdmin] FROM WINDOWS WITH DEFAULT_DATABASE=[Master]
            GO
            -- Create ExitLabSqlAgen login with users for all DB's
            CREATE LOGIN [ADATUM\ExitLabSqlAgent] FROM WINDOWS WITH DEFAULT_DATABASE=[Master]
            GO
            CREATE USER [ExitLabSqlAgent] FOR LOGIN [ADATUM\ExitLabSqlAgent]
            GO
            USE [Test_DB_full]
            GO
            CREATE USER [ExitLabSqlAgent] FOR LOGIN [ADATUM\ExitLabSqlAgent]
            GO
            USE [Test_DB_simple]
            GO
            CREATE USER [ExitLabSqlAgent] FOR LOGIN [ADATUM\ExitLabSqlAgent]
            GO
            USE [master]
            GO 
            CREATE USER [ExitLabSqlAgent] FOR LOGIN [ADATUM\ExitLabSqlAgent]
            GO
            USE [tempdb]
            GO
            CREATE USER [ExitLabSqlAgent] FOR LOGIN [ADATUM\ExitLabSqlAgent]
            GO
            USE [model]
            GO
            CREATE USER [ExitLabSqlAgent] FOR LOGIN [ADATUM\ExitLabSqlAgent]
            GO
            USE [msdb]
            GO
            CREATE USER [ExitLabSqlAgent] FOR LOGIN [ADATUM\ExitLabSqlAgent]
            GO

            -- Create ExitLabSqlUser login with users on users DB's
            CREATE LOGIN [ADATUM\ExitLabSqlUser] FROM WINDOWS WITH DEFAULT_DATABASE=[Test_DB_simple]
            GO
            USE [Test_DB_simple]
            GO
            CREATE USER [ExitLabSqlUser] FOR LOGIN [ADATUM\ExitLabSqlUser]
            USE [Test_DB_full]
            GO
            CREATE USER [ExitLabSqlUser] FOR LOGIN [ADATUM\ExitLabSqlUser]
            GO
"@

    # query to alter user roles
    [string]$AlterSqlUserRoles = @"
            -- ALTER ExitLabSqlAdmin roles
            USE [Master]
            GO
            ALTER SERVER ROLE [sysadmin] ADD MEMBER [ADATUM\ExitLabSqlAdmin]
            GO

            -- ALTER ExitLabSqlUser roles
            USE [Test_DB_simple]
            GO
            
            ALTER ROLE [db_datareader] ADD MEMBER [ExitLabSqlUser]
            ALTER ROLE [db_denydatawriter] ADD MEMBER [ExitLabSqlUser]
            
            USE [Test_DB_simple]
            GO
            ALTER ROLE [db_datareader] ADD MEMBER [ExitLabSqlUser]
            ALTER ROLE [db_denydatawriter] ADD MEMBER [ExitLabSqlUser]
            
            --ALTER ExitLabSqlAgent
            USE [Test_DB_simple]
            GO
            ALTER SERVER ROLE [diskadmin] ADD MEMBER [ADATUM\ExitLabSqlAgent]
            ALTER ROLE [db_denydatawriter] ADD MEMBER [ExitLabSqlAgent]
            ALTER ROLE [db_backupoperator] ADD MEMBER [ExitLabSqlAgent]

            USE [Test_DB_full]
            GO
            
            ALTER ROLE [db_denydatawriter] ADD MEMBER [ExitLabSqlAgent]
            ALTER ROLE [db_backupoperator] ADD MEMBER [ExitLabSqlAgent]
            
            USE [master]
            GO
            
            ALTER ROLE [db_denydatawriter] ADD MEMBER [ExitLabSqlAgent]
            ALTER ROLE [db_backupoperator] ADD MEMBER [ExitLabSqlAgent]
            GO
            
            USE [tempdb]
            GO
            
            ALTER ROLE [db_denydatawriter] ADD MEMBER [ExitLabSqlAgent]
            ALTER ROLE [db_backupoperator] ADD MEMBER [ExitLabSqlAgent]
            GO
            
            USE [model]
            GO
            
            ALTER ROLE [db_denydatawriter] ADD MEMBER [ExitLabSqlAgent]
            ALTER ROLE [db_backupoperator] ADD MEMBER [ExitLabSqlAgent]
            GO
            
            USE [msdb]
            GO
            
            ALTER ROLE [db_denydatawriter] ADD MEMBER [ExitLabSqlAgent]
            ALTER ROLE [db_backupoperator] ADD MEMBER [ExitLabSqlAgent]
            GO
"@
    # restore and create DB's
    [string]$RestoreSqlDb =@"
            USE [master]
            GO
            CREATE DATABASE [AdventureWorks2012] ON 
            ( FILENAME = N'H:\MSSQL\AdventureWorks2012_Data.mdf' ),
            ( FILENAME = N'H:\MSSQL\AdventureWorks2012_log.ldf' )
            FOR ATTACH
            GO
            
            BACKUP DATABASE [AdventureWorks2012] TO  DISK = N'H:\MSSQL\AdventureWorks2012.bak' WITH NOFORMAT, INIT,  NAME = N'AdventureWorks2012-Full Database Backup', SKIP, NOREWIND, NOUNLOAD,  STATS = 10, CHECKSUM
            GO
            declare @backupSetId as int
            select @backupSetId = position from msdb..backupset where database_name=N'AdventureWorks2012' and backup_set_id=(select max(backup_set_id) from msdb..backupset where database_name=N'AdventureWorks2012' )
            if @backupSetId is null begin raiserror(N'Verify failed. Backup information for database ''AdventureWorks2012'' not found.', 16, 1) end
            RESTORE VERIFYONLY FROM  DISK = N'H:\MSSQL\AdventureWorks2012.bak' WITH  FILE = @backupSetId,  NOUNLOAD,  NOREWIND
            GO
            
            EXEC master.dbo.xp_create_subdir "E:\Data";
            EXEC master.dbo.xp_create_subdir "F:\Log";

            USE [master]
            RESTORE DATABASE [Test_DB_simple] FROM  DISK = N'H:\MSSQL\AdventureWorks2012.bak' WITH  FILE = 1,  MOVE N'AdventureWorks2012_Data' TO N'E:\Data\Test_DB_simple.mdf',  MOVE N'AdventureWorks2012_Log' TO N'F:\Log\Test_DB_simple_log.ldf',  NOUNLOAD,  STATS = 5
            
            GO
            
            USE [master]
            GO
            ALTER DATABASE [Test_DB_simple] SET  READ_WRITE WITH NO_WAIT
            GO
            
            
            USE [master]
            RESTORE DATABASE [Test_DB_full] FROM  DISK = N'H:\MSSQL\AdventureWorks2012.bak' WITH  FILE = 1,  MOVE N'AdventureWorks2012_Data' TO N'E:\Data\Test_DB_full.mdf',  MOVE N'AdventureWorks2012_Log' TO N'F:\Log\Test_DB_full_log.ldf',  NOUNLOAD,  STATS = 5
            GO
            
            USE [master]
            GO
            ALTER DATABASE [Test_DB_full] SET  READ_WRITE WITH NO_WAIT
            GO
            ALTER DATABASE [Test_DB_full] SET RECOVERY FULL WITH NO_WAIT
            GO
"@
    # db encryption query
    [string]$EncryptSqlDb = @"
                
            -- Create and backup DB master key and DB certificate

            USE Master;
            CREATE MASTER KEY
                ENCRYPTION BY PASSWORD = 'Pa`$`$w0rd'

            CREATE CERTIFICATE Security_Certificate
                WITH SUBJECT = 'DEK_Certificate'

            BACKUP CERTIFICATE Security_Certificate 
                TO FILE = 'H:\MSSQL\security_cert.cer'
                WITH PRIVATE KEY
                (FILE = 'H:\MSSQL\security_cert.key',
                ENCRYPTION BY PASSWORD = 'CertPa`$`$w0rd');
                
            -- Create DB Encryption key

            USE Test_DB_full;

            CREATE DATABASE ENCRYPTION KEY
                WITH ALGORITHM = AES_128
                ENCRYPTION BY SERVER CERTIFICATE Security_Certificate;
                
            -- Enable encryption

            ALTER DATABASE Test_DB_full
                SET ENCRYPTION ON; 
            GO
"@
    # check encryption state
    [string]$CheckSqlEncryption = @"
        USE Master;
        SELECT name, is_encrypted from sys.databases
"@
    # dedlock alert
    [string]$CreateSqlDeadlockAlert = @"
        EXEC master.sys.sp_altermessage 1205, 'WITH_LOG', TRUE;
        GO
        EXEC master.sys.sp_altermessage 3928, 'WITH_LOG', TRUE;
        GO
        DBCC TRACEON (1204, -1)
        DBCC TRACEON (1222, -1)
        GO       
"@

    #endregion
    
    #region begin create DB's
    # restoring DB's and then recreating new one's
    "Creating DB's on SQL server..." | Write-Host -ForegroundColor Blue
    try 
        {
        Copy-Item -Path "C:\Training\M4 SQL\SQL_Server_Soft\AdventureWorks2012_Data.mdf" -Destination "H:\MSSQL\" -ToSession $PssSql
        Copy-Item -Path "C:\Training\M4 SQL\SQL_Server_Soft\AdventureWorks2012_log.ldf" -Destination "H:\MSSQL\" -ToSession $PssSql
        }
    catch 
        {
        ("[ERROR] Could not copy DB files to destination server ({0})" -f $SqlSrvrAddress) | Write-Error
        ExitWithCode -exitcode 9
        }
    
    Run-SqlQry -Query $RestoreSqlDb
    "OK" |  Write-Host -ForegroundColor Blue 
    #endregion

    # create logins, users, service application role on SQL server
    "Adding logins to SQL server..." | Write-Host -ForegroundColor Blue 
    Run-SqlQry -Query $CreateSqlLogins
    "OK" |  Write-Host -ForegroundColor Blue 

    # alter user permissions on SQL server
    "Altering user permissions ..." | Write-Host -ForegroundColor Blue     
    Run-SqlQry -Query $AlterSqlUserRoles
    "OK" | Write-Host -ForegroundColor Blue

    # encrypt DB Test_DB_full
    "Enabling encryption for Test_DB_full DB ..." | Write-Host -ForegroundColor Blue     
    Run-SqlQry -Query $EncryptSqlDb
    "OK" | Write-Host -ForegroundColor Blue
    
    # create deadlock alert
    Run-SqlQry -Query $CreateSqlDeadlockAlert
    }

End 
    {
    # check encryption
    "Enabling encryption for Test_DB_full DB ..." | Write-Host -ForegroundColor Blue     
    $CheckEncRslt = Run-SqlQry -Query $CheckSqlEncryption
    $CheckEncRslt
    }