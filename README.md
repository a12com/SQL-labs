# SQL-labs
labs on mssql autumn 2018
######################################
Lab2.1  task:

Prerequisites:
At least 1 running SQL server
At list 2 attached not system disk in the OS – to place users DBs files (ALL files of custom DBs)
Tools to work with SQL server 
Pay attention to best practices and performance optimization for SQL server and databases.
Tasks:
1.	Reconfigure TEMPDB to another database files location and options (use custom folder):
Main DB file:
Size: 10 MB
File growth: 5 MB
Maximum size: Unlimited
File location: on the attached disk

DB log file: 
Size: 10 Mb
File growth: 1 MB
Maximum size: Unlimited
File location: on the attached disk

Script it using PowerShell:
Code should be wrapped in PowerShell script, started from student local PC, Password isn’t provided as a plain text, errors capturing is active, code returns DB files locations before execution and after, check the existing files with the same name in the target location, and check free space on disk. To check DB with TSQL:
SELECT name, physical_name,size,max_size,growth  
FROM sys.master_files  
WHERE database_id = DB_ID(N'tempdb'); 

Script Lab2.1PS1
######################################

Lab2.2 task:

Logical Name	Filegroup	Initial Size	Growth	Path
HumanResources	PRIMARY	50 MB	5MB/Unlimited	D:\Data\HumanResources.mdf
HumanResources_log		5 MB 	1 MB/Unlimited	D:\Logs\HumanResources.ldf
InternetSales	PRIMARY	5 MB	1 MB / Unlimited	D:\Data\InternetSales.mdf
InternetSales_data1	SalesData	100 MB	10 MB / Unlimited	D:\Data\InternetSales_data1.ndf
InternetSales_data2	SalesData	100 MB	10 MB / Unlimited	D:\AdditionalData\InternetSales_data2.ndf
InternetSales_log		2 MB	10% / Unlimited	D:\Logs\InternetSales.ldf
Make the SalesData filegroup the default filegroup

1.	Wrap DBs creation in PS Script, lab task 2 should be executed as non-stop script with Human readable output,
all scripts start from Student local PC. Check if DBs with such names already exist, if yes – drop them with their files,
check if everything was succesfull, and create new DBs. NO REMOTE PS SESSIONS or invoke-expressions on remote PC.

Script Lab2.2.ps1
######################################

Lab2.3 task:

2.	Using PowerShell, create and run script from local PC, which deploys:
Data Base “PCDRIVE” (with parameters like HumanResources)
DB contains tables with results of command: 
Get-PhysicalDisk | select -Property FriendlyName,BusType,HealthStatus,Size,MediaType 

Data types and names for columns could be selected by yourself 
Compare pages and files sizes before and after filling data to DB (PS Script should show it in Human readable format).
Save logging of script actions with start and stop time of execution. (Decide what should be logged – it is your own choice).

Script Lab2.3.ps1



