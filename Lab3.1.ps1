<#
Task 1. Create a PowerShell wrapper for scenario, that should perform next:
1.	Create a backup for Adventure Work DB,  and restore it on the instance 1.
2.	Make update of any table with SELECT Before and SELECT after. 
3.	Create full compressed backup of DB
4.	Restore it on second Instance.
5.	Write everything in log file, Log file should be Human readable, with commented steps. (Tee-Object can help)

#>
# import module for work with SQL

Import-Module SqlServer

# create credentials

$UsrName = "SA"
Write-Output "Enter $UsrName password"
$Pwd = Read-host -AsSecureString
$Svr1Name = "lon-svr1"
$Svr2Name = "lon-svr2\INST2,1433"
$SACred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UsrName, $Pwd
 
# exitcode function
function ExitWithCode 
    {
        param ($exitcode, $Err=$Error[0],$Exc,$InnExc)
        $Exc=$NULL
        $InnExc=$NULL
        
        # Get Current Exception Value
        If ($Error[0].Exception -ne $NULL)
            {
                $Exc=$Err.exception
                WrtLog -text "$Exc`n"
            }

        # Check if there is a more exacting Error code in Inner Exception
        If ($Err.exception.InnerException -ne $NULL)
            {
                $InnExc=$Err.Exception.InnerException
                WrtLog -text "$InnExc`n"
            }

        # If No InnerException or Exception has been identified
        # Use GetBaseException Method to retrieve object
        if ($Exc -eq '' -and $InnExc -eq '')
            {
                $Exc=$Err.GetBaseException()
                WrtLog -text "$Exc`n"
            }
        
        $host.SetShouldExit($exitcode)
        WrtLog -text "Script sent exitcode ($exitcode)" 
        exit $exitcode
    }
    
# SQL query function (invoke-sqlcmd)
Function SqlQry 
    {
        Param([string]$Qry, [string]$SvrIns, $Credential=$SACred)
        Try
            {
                Invoke-SqlCmd -ServerInstance $SvrIns -Credential $Credential -Query $Qry -QueryTimeout 0 -ErrorAction Stop
                Start-Sleep -Milliseconds 1500
            }
        Catch
            {
                ExitWithCode -exitcode 10
            }
    }


# log file write function

Function WrtLog
    {
        Param([string]$text, [string]$filepath=$log)
        Write-Host "$text" -ForegroundColor Green
        $text | Out-File -FilePath $filepath -Append  
    }

# Create clear log file

$null | Out-File .\lab3.1.log
$log= '.\lab3.1.log'

# start of script timestamp

WrtLog -text "Starting of lab 3.1 script at:" 

$StartTime=Get-Date

Wrtlog -text $StartTime

# check existense of AdventureWorks2012 on server1

WrtLog -text "Cheking if DB AdventureWorks2012 exists..."

$DBExists = Get-SqlDatabase -name "Adventureworks2012" -ServerInstance $Svr1Name -Credential $SACred

If ( $DBExists.State -eq "Existing")
    {
        WrtLog -text "DB AdventureWorks2012 exists"
    }
else 
    {
        Wrtlog -text "Error. DB Adventureworks2012 does NOT exists. Script aborted"
        ExitWithCode -exitcode 404 
    }

# create backup of Adventureworks on server1

WrtLog -text "Creating DB AdventureWorks2012 backup..."

$Query = @"
BACKUP DATABASE [AdventureWorks2012] 
TO  DISK = N'H:\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Backup\AdventureWorks2012.bak' 
WITH   NOFORMAT, INIT,  
NAME = N'AdventureWorks2012 Full DB  Backup', 
SKIP, NOREWIND, NOUNLOAD,  STATS = 10, CHECKSUM
GO

DECLARE @backupSetId AS int
SELECT @backupSetId = position 
    FROM msdb..backupset 
    WHERE database_name=N'AdventureWorks2012' 
    AND backup_set_id=(select max(backup_set_id) 
    FROM msdb..backupset where database_name=N'AdventureWorks2012' )

IF @backupSetId IS NULL 
    BEGIN 
        RAISERROR(N'Verify failed. Backup information for database ''AdventureWorks2012'' not found.', 16, 1) 
    END

RESTORE VERIFYONLY 
    FROM  DISK = N'H:\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Backup\AdventureWorks2012.bak' 
    WITH  FILE = @backupSetId,  NOUNLOAD,  NOREWIND
GO
"@

SqlQry -SvrIns $Svr1Name -Qry $Query

# can do same thing with special cmdlet below:
<#
Try 
    {
        Backup-SqlDatabase -ServerInstance $Svr1Name -Database "AdventureWorks2012" -Credential $SACred -BackupFile "H:\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Backup\AdventureWorks2012.bak" -Checksum -initialize
    }

Catch 
    {
        ExitWithCode 12
    }
#>
WrtLog -text "OK"

# restore backup into new DB on Server 1 

WrtLog -text "Restoring backup into new DB named RestoredDB..."

$Query = @"
USE [master]
RESTORE DATABASE [RestoredDB] 
	FROM  DISK = N'H:\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Backup\AdventureWorks2012.bak' 
	WITH  FILE = 1,  MOVE N'AdventureWorks2012_Data' 
	TO N'C:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\DATA\RestoredDB_Data.mdf',  
	MOVE N'AdventureWorks2012_Log' 
	TO N'C:\Program Files\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\DATA\RestoredDB_log.ldf', 
	NOUNLOAD,  STATS = 5

GO
"@

SqlQry -SvrIns $Svr1Name -Qry $Query

WrtLog -text "OK"

# make an update to data in new DB

WrtLog -text "Updating data in RestoredDB"

$Query = @"
USE RestoredDB;

SELECT PhoneNumber From RestoredDB.Person.PersonPhone
WHERE BusinessEntityID = 260;

BEGIN TRAN
UPDATE RestoredDB.Person.PersonPhone
SET PhoneNumber='151-555-1234'
WHERE BusinessEntityID=260;

SELECT PhoneNumber From RestoredDB.Person.PersonPhone
WHERE BusinessEntityID = 260;

COMMIT TRAN	
------------------------------
SELECT DocumentSummary FROM RestoredDB.Production.Document
--WHERE Title = 'Maintenance'

BEGIN TRAN
UPDATE RestoredDB.Production.Document
SET DocumentSummary = 'Lack of maintenance is a reason of 99% failures'

SELECT DocumentSummary FROM RestoredDB.Production.Document
--WHERE Title = 'Maintenance'
COMMIT TRAN
------------------------------
SELECT * FROM RestoredDB.Sales.Currency 
	WHERE CurrencyCode like 'B%'

BEGIN TRAN
INSERT RestoredDB.Sales.Currency (CurrencyCode, Name)
VALUES ('BYN', 'Belarussian Rubles');

SELECT * FROM RestoredDB.Sales.Currency 
	WHERE CurrencyCode like 'B%'
COMMIT TRAN

"@

SqlQry -SvrIns $Svr1Name -Qry $Query

WrtLog -text "OK"

# create RestoredDB full backup

WrtLog -text "Creating DB RestoredDB backup..."

$Query = @"
BACKUP DATABASE [RestoredDB] 
TO  DISK = N'H:\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Backup\RestoredDB.bak' 
WITH   NOFORMAT, INIT,  
NAME = N'RestoredDB Full DB  Backup', 
SKIP, NOREWIND, NOUNLOAD, COMPRESSION, STATS = 10, CHECKSUM
GO

DECLARE @backupSetId AS int
SELECT @backupSetId = position 
    FROM msdb..backupset 
    WHERE database_name=N'RestoredDB' 
    AND backup_set_id=(select max(backup_set_id) 
    FROM msdb..backupset where database_name=N'RestoredDB' )

IF @backupSetId IS NULL 
    BEGIN 
        RAISERROR(N'Verify failed. Backup information for database ''RestoredDB'' not found.', 16, 1) 
    END

RESTORE VERIFYONLY 
    FROM  DISK = N'H:\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Backup\RestoredDB.bak' 
    WITH  FILE = @backupSetId,  NOUNLOAD,  NOREWIND
GO
"@

SqlQry -SvrIns $Svr1Name -Qry $Query

WrtLog -text "OK"

# Restore RestoredDB on 2nd server

WrtLog -text "Restoring RestoredDB on the $Svr2Name ..."

$Query = @"
USE [master]
RESTORE DATABASE [RestoredDB] 
FROM  DISK = N'\\lon-svr1\h_disk\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQL\Backup\RestoredDB.bak' 
WITH  FILE = 1,  
MOVE N'AdventureWorks2012_Data' 
TO N'C:\Program Files\Microsoft SQL Server\MSSQL11.INST2\MSSQL\DATA\RestoredDB_Data.mdf',  
MOVE N'AdventureWorks2012_Log' 
TO N'C:\Program Files\Microsoft SQL Server\MSSQL11.INST2\MSSQL\DATA\RestoredDB_log.ldf',  NOUNLOAD,  REPLACE,  STATS = 5

GO
"@

SqlQry -SvrIns $Svr2Name -Qry $Query

WrtLog -text "OK"

# End of script timestamp

$FinishTime = Get-Date
WrtLog "End of script time `n$FinishTime"