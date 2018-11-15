Import-Module SqlServer

# Create credentials
$UsrName = "SA"
Write-Output "Enter $UsrName password"
$Pwd = Read-host -AsSecureString
$SvrName = "lon-svr1"
$SACred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UsrName, $Pwd
 
# Create Exitcode function
function ExitWithCode 
    {
        param ($exitcode)

        $host.SetShouldExit($exitcode)
        WrtLog -text "$exitcode" 
        exit 
    }

# create SQL query function (invoke-sqlcmd)
Function SqlQry 
    {
        Param([string]$Qry, [string]$ServerInstance=$SvrName, $Credential=$SACred)
        Try
            {
                Invoke-SqlCmd -ServerInstance $ServerInstance -Credential $Credential -Query $Qry -QueryTimeout 0 -ErrorAction Stop
                Start-Sleep -Milliseconds 1500
            }
        Catch
            {
                ExitWithCode
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

$null | Out-File .\lab2.3.log
$log= '.\lab2.3.log'

# start of script timestamp

WrtLog -text "Starting of lab 2.3 script at:" 

$StartTime=Get-Date

Wrtlog -text $StartTime

# Get disk info

WrtLog -text "Getting disk info..."
$GPDsk = Get-PhysicalDisk | Select-Object -Property FriendlyName,BusType,HealthStatus,@{label='VolSize';expression={$_.Size} },MediaType | ConvertTo-Csv #| Set-Content -Path .\GtPD.csv

# insert data into temporary file and bring it back in CSV format

$GPDsk | Out-File -FilePath .\lab2.3.csv
$ImportCSV = Import-Csv -Path .\lab2.3.csv
Remove-Item -Path .\lab2.3.csv

If ($ImportCSV -ne $Null)
    {
        WrtLog -text "OK"
    }
else 
    {
        WrtLog -text "Error (no data)"
    }

# create DB PCDrive

WrtLog -text "Creating DB PCDrive..."

$query = @"
-- Check to see whether this stored procedure exists.  
IF OBJECT_ID (N'usp_GetErrorInfo', N'P') IS NOT NULL  
    DROP PROCEDURE usp_GetErrorInfo;  
GO  

-- Create procedure to retrieve error information.  
CREATE PROCEDURE usp_GetErrorInfo  
AS  
    SELECT   
         ERROR_NUMBER() AS ErrorNumber  
        ,ERROR_SEVERITY() AS ErrorSeverity  
        ,ERROR_STATE() AS ErrorState  
        ,ERROR_LINE () AS ErrorLine  
        ,ERROR_PROCEDURE() AS ErrorProcedure  
        ,ERROR_MESSAGE() AS ErrorMessage;  
GO  

BEGIN TRY  
	-- Check database exsitense
	IF DB_ID (N'PCDrive') IS NOT NULL
		BEGIN
			PRINT N' Database PCDrive exists. Trying to delete';
			DROP DATABASE PCDrive;
		END;

	IF DB_ID (N'PCDrive') IS NULL  
		PRINT N'Database PCDrive deleted successfully';    
	
	-- Check files and folders existence
	PRINT N'Checking if file E:\Data\PCDrive.mdf exists';
	EXEC master.dbo.xp_fileexist 'E:\Data\PCDrive.mdf';
	PRINT N'Checking if file E:\Logs\Humanresorces.ldf';
	EXEC master.dbo.xp_fileexist 'E:\Logs\PCDrive.ldf';
	EXEC master.dbo.xp_create_subdir "E:\Data";
	EXEC master.dbo.xp_create_subdir "E:\Logs";

	--Create database
	CREATE DATABASE PCDrive  
	ON PRIMARY  
		( NAME = PCDrive,  
		FILENAME = 'E:\Data\PCDrive.mdf',  
		SIZE = 50 MB,  
		MAXSIZE = UNLIMITED,  
		FILEGROWTH = 5 MB ) 
	LOG ON  
	( NAME = PCDrivelog,  
		FILENAME = 'E:\Logs\PCDrive.ldf',  
		SIZE = 5MB,  
		MAXSIZE = UNLIMITED,  
		FILEGROWTH = 1MB ) ;  
	
END TRY  
BEGIN CATCH  
	EXECUTE usp_GetErrorInfo;

END CATCH; 
GO 

-- Check database exsitense
IF DB_ID (N'PCDrive') IS NOT NULL  
PRINT N'Database PCDrive created successfully'; 
"@

SqlQry -Qry $query

# Get DBs info at start

$Query = @"
USE PCDrive;
GO

SELECT SUM(user_object_reserved_page_count) AS [user object pages used],  
(SUM(user_object_reserved_page_count)*1.0/128) AS [user object space in MB]  
FROM sys.dm_db_file_space_usage;
"@

$PCDriveInfoStrt = SqlQry -Qry $query

if ($PCDriveInfoStrt -ne $null)
    {WrtLog -text "OK"}

#Write-Host "PCDrive usage info:" -ForegroundColor Green
#$PCDriveInfoStrt | Format-Table

# Create table

$query = @"
USE PCDrive;
GO

-- Create table 
IF OBJECT_ID('tbl_PhysicalDisk', 'U') IS NOT NULL 
    DROP TABLE dbo.tbl_PhysicalDisk;

CREATE TABLE tbl_PhysicalDisk
(
[FriendlyName] VARCHAR(40) not null,
[BusType] VARCHAR(40),
[HealthStatus] VARCHAR(40),
[VolSizeGB] int,
[MediaType] VARCHAR(40)
)
"@

SqlQry -Qry $query
WrtLog -text "Creating table..."

# Check table creation

$query=@"
USE PCDrive;
GO

IF OBJECT_ID('tbl_PhysicalDisk', 'U') IS NOT NULL 
    SELECT 1 AS result ELSE SELECT 0 AS result;
"@

$ChkTblExstnc = SqlQry -Qry $query

If ($ChkTblExstnc.result)
    {
        Write-Host "Table tbl_PhysicalDisk created successfully" -ForegroundColor Green
        WrtLog -text "OK"
    }
Else 
    {
        WrtLog "Error creating table tbl_PhysiscalDisk"
        Write-Error "Error creating table tbl_PhysicalDisk"
        Exit
    }

# insert data into temporary table

WrtLog -text "Adding data to tbl_PhysicalDisk..."
ForEach ($row in $ImportCSV)
    {
        $CsvRecFriendlyName = $row.FriendlyName
        $CsvRecBusType = $row.BusType
        $CsvRecHealthStatus = $row.HealthStatus
        $CsvRecVolSize = [Math]::Round($row.VolSize / 1GB,0)
        $CsvRecMediaType = $row.MediaType
        $SqlIns = @"
                USE PCDrive
                INSERT INTO tbl_PhysicalDisk (FriendlyName, BusType, HealthStatus, VolSizeGB, MediaType)
                VALUES('$CsvRecFriendlyName', '$CsvRecBusType', '$CsvRecHealthStatus', '$CsvRecVolSize','$CsvRecMediaType');
"@
        try 
            {
                SqlQry -Qry $SqlIns
            }
        catch 
            {
                ExitWithCode
            }
    }
WrtLog -text "OK"

# End of script timestamp

$FinishTime = Get-Date
WrtLog "End of script time `n$FinishTime"

# Get DBs info at the end of script

$Query = @"
USE PCDrive;
GO

SELECT SUM(user_object_reserved_page_count) AS [user object pages used],  
(SUM(user_object_reserved_page_count)*1.0/128) AS [user object space in MB]  
FROM sys.dm_db_file_space_usage;
"@

$PCDriveInfoFnsh = SqlQry -Qry $query

Write-Host "PCDrive usage info at the start is:" -ForegroundColor Green
$PCDriveInfoStrt | Format-Table

Write-Host "PCDrive usage info at the end is:" -ForegroundColor Green
$PCDriveInfoFnsh | Format-Table
