SQL-labs<br>
<i>Labs on mssql autumn 2018</i>

<hr>

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

<hr>

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
<hr>

Lab2.3 task:

2.	Using PowerShell, create and run script from local PC, which deploys:
Data Base “PCDRIVE” (with parameters like HumanResources)
DB contains tables with results of command: 
Get-PhysicalDisk | select -Property FriendlyName,BusType,HealthStatus,Size,MediaType 

Data types and names for columns could be selected by yourself 
Compare pages and files sizes before and after filling data to DB (PS Script should show it in Human readable format).
Save logging of script actions with start and stop time of execution. (Decide what should be logged – it is your own choice).

Script Lab2.3.ps1

<hr>

Lab3.1 task:

Task 1. Create a PowerShell wrapper for scenario, that should perform next:
1.	Create a backup for Adventure Work DB,  and restore it on the instance 1.
2.	Make update of any table with SELECT Before and SELECT after. 
3.	Create full compressed backup of DB
4.	Restore it on second Instance.
5.	Write everything in log file, Log file should be Human readable, with commented steps. (Tee-Object can help)

Script Lab3.1.ps1


<hr>

Lab3.2 task:


For self studying: “Importing and Exporting Data” in courseware	
Extra task for lab 3:
Purpose: Using any code-based option of Data import, Import your custom data in SQL.
Prerequisites:
You have a task to gather information about 100+ VMs, that new customer hosts in private datacenter
VMs is windows based, most of them has no GUI
You should form a document, that contains next options:
•	VM host name
•	VM OS name 
•	VM OS version
•	CPU count
•	Memory count (RAM)
•	.Net Framework version
And import this document to SQL data base, there BI team could process it
Lab task: 
Create a script witch does all described above, create a file with output, and import it into SQL table, named as host
For now it is OK to gather data for 1 Host
Import data tool could be chosen by you, the idea is to do all automatically, not manually


Script Lab3.2.ps1

<hr>

Lab 4.1 task:

Make a PowerShell wrapper script to handle Users creation and database encryption (for one instance).
Read configuration with users from CSV file (columns: Function – DEV, test, service app, service user, backup user; Username – usernames; Password – User Passwords). May use the same config to create users in your AD/Local Computer accounts.  

On first server (as DEV instance):	
5 developers:	Read and write the database data of User DB. No access to System DBs
1 application service (non-human user, service account)	Read/write/update data in the table of User DB. No access to System DBs
1 service account (non-application user, the service account for maintenance)	Modify user DB, create backups, but do not delete DB. Read systems DB.
1 user, who should make backups	Make backups of all DB, but cannot read data from User DB
2 QA users	Can only read data from user DB

Script Lab4.1.ps1
