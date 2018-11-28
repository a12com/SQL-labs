<# Lab 4.1
Make a PowerShell wrapper script to handle Users creation and database encryption (for one instance).
Read configuration with users from CSV file (columns: Function – DEV, test, service app, service user, backup user; Username – usernames; Password – User Passwords). May use the same config to create users in your AD/Local Computer accounts.  
On first server (as DEV instance):	
5 developers:	Read and write the database data of User DB. No access to System DBs
1 application service (non-human user, service account)	Read/write/update data in the table of User DB. No access to System DBs
1 service account (non-application user, the service account for maintenance)	Modify user DB, create backups, but do not delete DB. Read systems DB.
1 user, who should make backups	Make backups of all DB, but cannot read data from User DB
2 QA users	Can only read data from user DB
#>

Param
    (
    # addresses of DC and SQL servers and DB name
    [string]$DcSrvr = "lon-dc1",
    [string]$SqlSrvr = "lon-svr1",
    [string]$SqlDbName = "Test_Bohush"
    )

Begin
    {
    # import module to work with SQL
    Import-Module SqlServer
    
    #region begin credetials
    # create credentials
    [string]$SqlUsrName = "SA"
    Write-Output ("Enter {0} password" -f $SqlUsrName)
    $SqlPwd = Read-Host -AsSecureString
    $SqlCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $SqlUsrName, $SqlPwd
    [string]$DomainName = "Adatum"
    $DcCred = Get-Credential ("{0}\Administrator" -f $DomainName)
    
    #endregion

    #region begin log file
    # create log file and put start time there
    [string]$LogFilePath = (".\lab4.1({0}).log" -f (Get-Date -Uformat %r | foreach {$_ -replace ":","."}) )
    $null | Out-File -FilePath $LogFilePath
    Write-Host ("Script log created in file {0}" -f $LogFilePath)
    [string]$Time = ("Started script at {0}" -f (Get-Date) )
    $Time | Out-File -FilePath $LogFilePath
    #endregion

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

    # SQL query function (invoke-sqlcmd)
    Function Run-SqlQry 
        {
        Param
        (
        [string]$Query,
        [string]$SrvrIns=$SqlSrvr,
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
    
    #region begin get user list
    # get userlist
    try
        {
        $UserList = Import-Csv '.\userlist.csv'
        }
    catch
        {
        "[ERROR] User list not found" | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Red 
        ExitWithCode -exitcode 12
        }
    #endregion

    #region begin create pssession with DC
    # create pssession to work with DC server
    try 
        {
        $PSS = $Null
        $PssOption = New-PSSessionOption -OpenTimeout 30 -CancelTimeout 30 -OperationTimeout 30
        $PSS = New-PSSession -ComputerName $DcSrvr -Credential $DcCred -SessionOption $PssOption

        }
    catch 
        {
        ("[ERROR] Could not connect to {0}" -f $DcSrvr) | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Red 
        ExitWith-Code -ExitCode 4
        }
    #endregion

    #region begin SQL queries to run
    
    # get all DB names on SQL instance
    $SqlDbList = Run-SqlQry -Query "SELECT name FROM master.sys.databases"

    # assemble query to assign logins on SQL server
    [string]$CreateSqlLogins = ("USE [{0}]`nGO`n" -f $SqlDbName)
    foreach ($User in $UserList)
        {
        # firstly asseble SQL login query
        [string]$AddStringLogin = ("CREATE LOGIN [{0}\{1}] FROM WINDOWS WITH DEFAULT_DATABASE=[{2}]`nGO`n" -f $DomainName, $User.Username, $SqlDbName )
        # add user\or server application role
        switch ($User.Function)
            {
            # for users with functions dev and test only one DB
            {$_ -in "dev","test"}
                {
                [string]$AddStringUser = ("USE [{0}]`nGO`nCREATE USER [{1}] FOR LOGIN [{2}\{1}]`nGO`n`n" -f $SqlDbName, $User.Username, $DomainName)
                }
            # for service and backup users all DB's
            {$_ -in "service user","backup user"}
                {
                [string]$AddStringUser = $null
                foreach ($Db in $SqlDbList.name)
                    {
                    [string]$AddStringUserForDb = ("USE [{0}]`nGO`nCREATE USER [{1}] FOR LOGIN [{2}\{1}]`nGO`n`n" -f $Db, $User.Username, $DomainName)
                    $AddStringUser += $AddStringUserForDb
                    }
                }
            # service role for application
            ("service app") 
                {
                [string]$AddStringUser = ("USE[{0}]`nGO`nCREATE APPLICATION ROLE [{1}] WITH PASSWORD = N'{2}'`nGO`n`n" -f $SqlDbName, $User.Username, $User.Password )
                }
            }
        $CreateSqlLogins = $CreateSqlLogins + $AddStringLogin + $AddStringUser
        }

    # unfortunately we couldn't automate this part so we have to put write it down manually
    [string]$AlterSqlUserRoles = @"
        -- ALTER Dev roles
        USE [Test_Bohush]
        GO
        
        ALTER ROLE [db_datareader] ADD MEMBER [Dev1]
        ALTER ROLE [db_datawriter] ADD MEMBER [Dev1]
        ALTER ROLE [db_datareader] ADD MEMBER [Dev2]
        ALTER ROLE [db_datawriter] ADD MEMBER [Dev2]
        ALTER ROLE [db_datareader] ADD MEMBER [Dev3]
        ALTER ROLE [db_datawriter] ADD MEMBER [Dev3]
        ALTER ROLE [db_datareader] ADD MEMBER [Dev4]
        ALTER ROLE [db_datawriter] ADD MEMBER [Dev4]
        ALTER ROLE [db_datareader] ADD MEMBER [Dev5]
        ALTER ROLE [db_datawriter] ADD MEMBER [Dev5]
        GO
        
        -- ALTER QA roles
        USE [Test_Bohush]
        GO
        
        ALTER ROLE [db_datareader] ADD MEMBER [QA1]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [QA1]
        ALTER ROLE [db_datareader] ADD MEMBER [QA2]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [QA2]
        
        --GRANT TABLE view, read, write for Server app role
        USE [Test_Bohush]
        GO
        
        GRANT ALTER ON [dbo].[AppTable] TO [Service app]
        GRANT INSERT ON [dbo].[AppTable] TO [Service app]
        GRANT SELECT ON [dbo].[AppTable] TO [Service app]
        GRANT UPDATE ON [dbo].[AppTable] TO [Service app]
        GRANT VIEW CHANGE TRACKING ON [dbo].[AppTable] TO [Service app]
        GRANT VIEW DEFINITION ON [dbo].[AppTable] TO [Service app]
        
        --ALTER Service User
        USE [Test_Bohush]
        GO
        
        ALTER ROLE [db_datawriter] ADD MEMBER [Service user]
        ALTER ROLE [db_backupoperator] ADD MEMBER [Service user]
        DENY DELETE TO [Service user]
        
        USE [master]
        GO
        
        ALTER ROLE [db_datareader] ADD MEMBER [Service user]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [Service user]
        GO
        
        USE [tempdb]
        GO
        
        ALTER ROLE [db_datareader] ADD MEMBER [Service user]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [Service user]
        GO
        
        USE [model]
        GO
        
        ALTER ROLE [db_datareader] ADD MEMBER [Service user]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [Service user]
        GO
        
        USE [msdb]
        GO
        
        ALTER ROLE [db_datareader] ADD MEMBER [Service user]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [Service user]
        GO
        
        --ALTER Backup user
        USE [master]
        GO
        
        ALTER ROLE [db_backupoperator] ADD MEMBER [Backup user]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [Backup user]
        GO
        
        USE [tempdb]
        GO
        
        ALTER ROLE [db_backupoperator] ADD MEMBER [Backup user]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [Backup user]
        GO
        
        USE [model]
        GO
        
        ALTER ROLE [db_backupoperator] ADD MEMBER [Backup user]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [Backup user]
        GO
        
        USE [msdb]
        GO
        
        ALTER ROLE [db_backupoperator] ADD MEMBER [Backup user]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [Backup user]
        GO
        
        USE [Test_Bohush]
        GO
        
        ALTER ROLE [db_backupoperator] ADD MEMBER [Backup user]
        ALTER ROLE [db_denydatawriter] ADD MEMBER [Backup user]
        ALTER ROLE [db_denydatareader] ADD MEMBER [Backup user]
        GO    
"@
    
    # db encryption query
    [string]$EncryptSqlDb = @"
                
        -- Create and backup DB master key and DB certificate

        USE Master;
        CREATE MASTER KEY
            ENCRYPTION BY PASSWORD = 'Pa$$w0rd'

        CREATE CERTIFICATE Security_Certificate
            WITH SUBJECT = 'DEK_Certificate'

        BACKUP CERTIFICATE Security_Certificate 
            TO FILE = 'E:\data\security_cert.cer'
            WITH PRIVATE KEY
            (FILE = 'e:\data\security_cert.key',
            ENCRYPTION BY PASSWORD = 'CertPa$$w0rd');
            
        -- Create DB Encryption key

        USE Test_Bohush;

        CREATE DATABASE ENCRYPTION KEY
            WITH ALGORITHM = AES_128
            ENCRYPTION BY SERVER CERTIFICATE Security_Certificate;
            
        -- Enable encryption

        ALTER DATABASE Test_Bohush
            SET ENCRYPTION ON; 
        GO
"@
    # check encryption state
    [string]$CheckSqlEncryption = @"
        USE Master;
        SELECT name, is_encrypted from sys.databases
"@

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
            ( "User {0} successfully created on DC {1}" -f $User.name, $DcSrvr) | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Blue
            }
        catch 
            {
            ( "[ERROR] Could not create user {0} on {1}" -f $User.Username, $DcSrvr ) | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Red 
            $Error[0] | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Red 
            }        
        }
    #endregion
    
    #region begin create Logins and users in SQL
    
    # create logins, users, service application role on SQL server
    "Adding logins to SQL server..." | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Blue 
    Run-SqlQry -Query $CreateSqlLogins
    "OK" | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Blue 
    
    # alter user permissions on SQL server
    "Altering user permissions ..." | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Blue     
    Run-SqlQry -Query $AlterSqlUserRoles
    "OK" | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Blue
    #endregion
    
    #region begin encrypt DB on SQL server
    
    # create and backup master key and DB certificate
    ("Encrypting DB {0} ..." -f $SqlDbName) | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Blue     
    Run-SqlQry -Query $EncryptSqlDb
    "OK" | Tee-Object -FilePath $LogFilePath -Append | Write-Host -ForegroundColor Blue
    #endregion   
    }
    
End
    {
    # check SQL server DB's for encryption
    Run-SqlQry -Query $CheckSqlEncryption | Out-File -FilePath $LogFilePath -Append
    
    # write down end of script time
    [string]$Time = ("Ended script at {0}" -f (Get-Date) )
    $Time | Out-File -FilePath $LogFilePath
    }










