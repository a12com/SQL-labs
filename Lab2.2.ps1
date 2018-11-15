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
        exit 
    }

# Create DBs

$Query = @"
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
	IF DB_ID (N'HumanResources') IS NOT NULL
		BEGIN
			PRINT N' Database HumanResources exists. Trying to delete';
			DROP DATABASE HumanResources;
		END;

	IF DB_ID (N'HumanResources') IS NULL  
		PRINT N'Database HumanResources deleted successfully';    
	
	-- Check files and folders existence
	PRINT N'Checking if file E:\Data\Humanresources.mdf exists';
	EXEC master.dbo.xp_fileexist 'E:\Data\HumanResources.mdf';
	PRINT N'Checking if file E:\Logs\Humanresorces.ldf';
	EXEC master.dbo.xp_fileexist 'E:\Logs\HumanResources.ldf';
	EXEC master.dbo.xp_create_subdir "E:\Data";
	EXEC master.dbo.xp_create_subdir "E:\Logs";

	--Create database
	CREATE DATABASE HumanResources  
	ON PRIMARY  
		( NAME = HumanResources,  
		FILENAME = 'E:\Data\HumanResources.mdf',  
		SIZE = 50 MB,  
		MAXSIZE = UNLIMITED,  
		FILEGROWTH = 5 MB ) 
	LOG ON  
	( NAME = HumanResourceslog,  
		FILENAME = 'E:\Logs\HumanResources.ldf',  
		SIZE = 5MB,  
		MAXSIZE = UNLIMITED,  
		FILEGROWTH = 1MB ) ;  
	
END TRY  
BEGIN CATCH  
	EXECUTE usp_GetErrorInfo;

END CATCH; 
GO 

-- Check database exsitense
IF DB_ID (N'HumanResources') IS NOT NULL  
PRINT N'Database HumanResources created successfully'; 

BEGIN TRY   
	IF DB_ID (N'InternetSales') IS NOT NULL
		BEGIN
			PRINT N' Database InternetSales exists. Trying to delete';
			DROP DATABASE InternetSales;
		END

	IF DB_ID (N'InternetSales') IS NULL
	PRINT N' Database InternetSales deleted successfully';

	-- Check files and folders existence
	PRINT N'Checking if files E:\Data\InternetSales.mdf exists';
	EXEC master.dbo.xp_fileexist 'E:\Data\InternetSales.mdf';
	PRINT N'Checking if files E:\Data\InternetSales_data1.ndf exists';
	EXEC master.dbo.xp_fileexist 'E:\Data\InternetSales_data1.ndf';
	PRINT N'Checking if files E:\AdditionalData\InternetSales_data2.ndf exists';
	EXEC master.dbo.xp_fileexist 'E:\AdditionalData\InternetSales_data2.ndf';
	PRINT N'Checking if files E:\Logs\InternetSales.ldf exists';
	EXEC master.dbo.xp_fileexist 'E:\Logs\InternetSales.ldf';
	EXEC master.dbo.xp_create_subdir "E:\Data";
	EXEC master.dbo.xp_create_subdir "E:\AdditionalData";
	EXEC master.dbo.xp_create_subdir "E:\Logs";

	--Create database
	CREATE DATABASE InternetSales  
		ON PRIMARY  
		( NAME = InternetSales,  
		FILENAME = 'E:\Data\InternetSales.mdf',  
		SIZE = 5 MB,  
		MAXSIZE = UNLIMITED,  
		FILEGROWTH = 1 MB ),
	FILEGROUP SalesData
		( NAME = InternetSales_data1,  
		FILENAME = 'E:\Data\InternetSales_data1.ndf',  
		SIZE = 100 MB,  
		MAXSIZE = UNLIMITED,  
		FILEGROWTH = 10 MB ),
		( NAME = InternetSales_data2,  
		FILENAME = 'E:\AdditionalData\InternetSales_data2.ndf',  
		SIZE = 100 MB,  
		MAXSIZE = UNLIMITED,  
		FILEGROWTH = 10 MB )
	LOG ON  
		( NAME = InternetSales_log,  
		FILENAME = 'E:\Logs\InternetSales.ldf',  
		SIZE = 2MB,  
		MAXSIZE = UNLIMITED,  
		FILEGROWTH = 10% ) ;  
	
	--Alter default filegroup
	ALTER DATABASE InternetSales
		MODIFY FILEGROUP SalesData DEFAULT;

END TRY
BEGIN CATCH  
	EXECUTE usp_GetErrorInfo;

END CATCH; 

IF DB_ID (N'InternetSales') IS NOT NULL
	PRINT N' Database InternetSales created successfully';
GO 
"@

Try
    {
        Invoke-SqlCmd -ServerInstance $SvrName -Credential $SACred -Query $Query -Verbose 
    }
Catch 
    {
        ExitWithCode
    }

# Get DBs info

$Query = @"
SELECT name, physical_name,size * 8 / 1024 'Size MB' ,max_size,growth * 8 / 1024 'Growth MB'
FROM sys.master_files  
WHERE database_id = DB_ID(N'HumanResources'); 
"@

$HumanResourcesInfo = Invoke-Sqlcmd -ServerInstance $SvrName -Credential $SACred -Query $Query 
Write-Host "HumanResources files are:" -ForegroundColor Green
$HumanResourcesInfo | Format-Table

$Query = @"
USE InternetSales;  
GO  

SELECT name, physical_name,size * 8 / 1024 'Size MB' ,max_size,growth 
FROM sys.master_files  
WHERE database_id = DB_ID(N'InternetSales'); 
"@
$InternetSalesInfo = Invoke-Sqlcmd -ServerInstance $SvrName -Credential $SACred -Query $Query 
Write-Host "InternetSales files are:" -ForegroundColor Green
$InternetSalesInfo | Format-Table

$Query = @"
SELECT SUM(user_object_reserved_page_count) AS [user object pages used],  
(SUM(user_object_reserved_page_count)*1.0/128) AS [user object space in MB]  
FROM sys.dm_db_file_space_usage;
"@
$InternetSalesInfo2 = Invoke-Sqlcmd -ServerInstance $SvrName -Credential $SACred -Query $Query 
Write-Host "InternetSales usage info:" -ForegroundColor Green
$InternetSalesInfo2 | Format-Table

