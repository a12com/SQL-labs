#Lab 3.2

<#	
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
#>

Import-Module SqlServer

# Create credentials
$UsrName = "SA"
Write-Output "Enter $UsrName password"
$Pwd = Read-host -AsSecureString
$SACred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UsrName, $Pwd
$SqlSrvr = "lon-svr1"
$SysCred = Get-Credential "Adatum\Administrator"

# Create pssession to work with remote server

$PsOps = New-PSSessionOption -OpenTimeout 30 -CancelTimeout 30 -OperationTimeout 30
#$PSS = New-PSSession -ComputerName $SvrName -Credential $SysCred -SessionOption $PsOps

# exitcode function
function ExitWithCode 
    {
        param ($exitcode, $Err=$Error[0])
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
        Param([string]$Qry, [string]$SvrIns=$SqlSrvr, $Credential=$SACred)
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


# get .Net verion
# source https://github.com/AutomatedLab/AutomatedLab.Common/blob/develop/AutomatedLab.Common/Common/Public/Get-DotNetFrameworkVersion.ps1

function Get-DotNetFrameworkVersion
{
    param(
        [string]$ComputerName = $env:COMPUTERNAME
    )

    $dotNetRegistry  = 'SOFTWARE\Microsoft\NET Framework Setup\NDP'
    $dotNet4Registry = 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
    $dotNet4Builds = @{
        '30319'  = @{ Version = [System.Version]'4.0'                                                     }
        '378389' = @{ Version = [System.Version]'4.5'                                                     }
        '378675' = @{ Version = [System.Version]'4.5.1'   ; Comment = '(8.1/2012R2)'                      }
        '378758' = @{ Version = [System.Version]'4.5.1'   ; Comment = '(8/7 SP1/Vista SP2)'               }
        '379893' = @{ Version = [System.Version]'4.5.2'                                                   }
        '380042' = @{ Version = [System.Version]'4.5'     ; Comment = 'and later with KB3168275 rollup'   }
        '393295' = @{ Version = [System.Version]'4.6'     ; Comment = '(Windows 10)'                      }
        '393297' = @{ Version = [System.Version]'4.6'     ; Comment = '(NON Windows 10)'                  }
        '394254' = @{ Version = [System.Version]'4.6.1'   ; Comment = '(Windows 10)'                      }
        '394271' = @{ Version = [System.Version]'4.6.1'   ; Comment = '(NON Windows 10)'                  }
        '394802' = @{ Version = [System.Version]'4.6.2'   ; Comment = '(Windows 10 1607)'                 }
        '394806' = @{ Version = [System.Version]'4.6.2'   ; Comment = '(NON Windows 10)'                  }
        '460798' = @{ Version = [System.Version]'4.7'     ; Comment = '(Windows 10 1703)'                 }
        '460805' = @{ Version = [System.Version]'4.7'     ; Comment = '(NON Windows 10)'                  }
        '461308' = @{ Version = [System.Version]'4.7.1'   ; Comment = '(Windows 10 1709)'                 }
        '461310' = @{ Version = [System.Version]'4.7.1'   ; Comment = '(NON Windows 10)'                  }
        '461808' = @{ Version = [System.Version]'4.7.2'   ; Comment = '(Windows 10 1803)'                 }
        '461814' = @{ Version = [System.Version]'4.7.2'   ; Comment = '(NON Windows 10)'                  }
    }


        if($regKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $ComputerName))
        {
            if ($netRegKey = $regKey.OpenSubKey("$dotNetRegistry"))
            {
                foreach ($versionKeyName in $netRegKey.GetSubKeyNames())
                {
                    if ($versionKeyName -match '^v[123]') {
                        $versionKey = $netRegKey.OpenSubKey($versionKeyName)
                        $version = [System.Version]($versionKey.GetValue('Version', ''))
                        New-Object -TypeName PSObject -Property ([ordered]@{
                                ComputerName = $computer
                                Build = $version.Build
                                Version = $version
                                Comment = ''
                        })
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
                        Comment = $dotNet4Builds["$net4Release"].Comment
                })
            }
        }

}


Function WrtLog
    {
        Param([string]$text, [string]$filepath=$log)
        Write-Host "$text" -ForegroundColor Green
        $text | Out-File -FilePath $filepath -Append  
    }

# Create clear log file

$null | Out-File .\lab3.2.log
$log= '.\lab3.2.log'

# start of script timestamp

WrtLog -text "Starting of lab 3.2 script at:" 

$StartTime=Get-Date

Wrtlog -text $StartTime

# get server addresses

Try 
    {
        $SrvrLst= Get-Content -Path .\servers.txt
    } 
Catch 
    {
        ExitWithCode -exitcodem 1
    }

# reaching servers to get data and than putting it into $SrvrInfo

$SrvrInfo = @()
Foreach ($Server in $SrvrLst)
        {
            $PSS = $Null
            $VMHostName = $VMHostOsName = $VMHostOsVersion = $VMHostCpuCount = $VMHostMemory = $VMHostNetVer = $null
            try 
            {
                $PSS = New-PSSession -ComputerName $Server -Credential $SysCred -SessionOption $PsOps

                $VMHostName = Invoke-Command -Session $PSS -ScriptBlock {(Get-WmiObject -Class Win32_ComputerSystem).Name}
                $VMHostOsName = Invoke-Command -Session $PSS -ScriptBlock {(Get-WmiObject -class Win32_OperatingSystem).Caption}
                $VMHostOsVersion = Invoke-Command -Session $PSS -ScriptBlock {(Get-WmiObject -class Win32_OperatingSystem).version}
                $VMHostCpuCount = Invoke-Command -Session $PSS -ScriptBlock {(Get-WmiObject -Class Win32_Processor).NumberOfCores}
                $VMHostMemory = [Math]::Round(((Invoke-Command -Session $PSS -ScriptBlock {(Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory}) / 1mb),0)
                $VMHostNetVer = Invoke-Command -Session $PSS -ScriptBlock ${Function:Get-DotNetFrameworkVersion} | Select-Object -Property Version
                
            }
            catch 
            {
                WrtLog "Could not connect $Server"
                $VMHostName = "Server unreacheable"
            }
            $VMHostNetVer = $VMHostNetVer | ConvertTo-Csv # convert dot net result to string format
            $VMHostNetVer = $VMHostNetVer | ConvertTo-Csv
            $CurrSrvr = New-Object PSObject
            $CurrSrvr | Add-Member NoteProperty "Server address" $server
            $CurrSrvr | Add-Member NoteProperty "HostName" $VMHostName
            $CurrSrvr | Add-Member NoteProperty "OS name" $VMHostOsName
            $CurrSrvr | Add-Member NoteProperty "OS version" $VMHostOsVersion
            $CurrSrvr | Add-Member NoteProperty "CPU count" $VMHostCpuCount
            $CurrSrvr | Add-Member NoteProperty "Memory" $VMHostMemory
            $CurrSrvr | Add-Member NoteProperty "DotNet version" $VMHostNetVer

            $SrvrInfo += $CurrSrvr

        }

# insert data into temporary file and bring it back in CSV format

$SrvrInfo| ConvertTo-Csv | Out-File -FilePath .\lab3.2.csv
$ImportCSV = Import-Csv -Path .\lab3.2.csv
Remove-Item -Path .\lab3.2.csv

If ($ImportCSV -ne $Null)
    {
        WrtLog -text "OK"
    }
else 
    {
        WrtLog -text "Error (no data)"
    }

# create DB HostInfo

WrtLog -text "Creating DB HostInfo..."

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
	IF DB_ID (N'HostInfo') IS NOT NULL
		BEGIN
			PRINT N' Database HostInfo exists. Trying to delete';
			DROP DATABASE HostInfo;
		END;

	IF DB_ID (N'HostInfo') IS NULL  
		PRINT N'Database HostInfo deleted successfully';    
	
	-- Check files and folders existence
	PRINT N'Checking if file E:\Data\HostInfo.mdf exists';
	EXEC master.dbo.xp_fileexist 'E:\Data\HostInfo.mdf';
	PRINT N'Checking if file E:\Logs\Humanresorces.ldf';
	EXEC master.dbo.xp_fileexist 'E:\Logs\HostInfo.ldf';
	EXEC master.dbo.xp_create_subdir "E:\Data";
	EXEC master.dbo.xp_create_subdir "E:\Logs";

	--Create database
	CREATE DATABASE HostInfo  
	ON PRIMARY  
		( NAME = HostInfo_data,  
		FILENAME = 'E:\Data\HostInfo.mdf',  
		SIZE = 50 MB,  
		MAXSIZE = UNLIMITED,  
		FILEGROWTH = 5 MB ) 
	LOG ON  
	( NAME = HostInfolog,  
		FILENAME = 'E:\Logs\HostInfo.ldf',  
		SIZE = 5MB,  
		MAXSIZE = UNLIMITED,  
		FILEGROWTH = 1MB ) ;  
	
END TRY  
BEGIN CATCH  
	EXECUTE usp_GetErrorInfo;

END CATCH; 
GO 

-- Check database exsitense
IF DB_ID (N'HostInfo') IS NOT NULL  
PRINT N'Database HostInfo created successfully'; 
"@

SqlQry -Qry $query

# Create table

$query = @"
USE HostInfo;
GO

-- Create table 
IF OBJECT_ID('Host', 'U') IS NOT NULL 
    DROP TABLE dbo.Host;

CREATE TABLE Host
(
[Server address] VARCHAR(50) not null,
[Host name] VARCHAR(50),
[OS name] VARCHAR(50),
[OS Version] VARCHAR(50),
[CPU count] INT,
[Memory] INT,
[DotNet version] VARCHAR(50)
)
"@

SqlQry -Qry $query
WrtLog -text "Creating table..."

# Check table creation

$query=@"
USE HostInfo;
GO

IF OBJECT_ID('Host', 'U') IS NOT NULL 
    SELECT 1 AS result ELSE SELECT 0 AS result;
"@

$ChkTblExstnc = SqlQry -Qry $query

If ($ChkTblExstnc.result)
    {
        Write-Host "Table Host created successfully" -ForegroundColor Green
        WrtLog -text "OK"
    }
Else 
    {
        WrtLog "Error creating table Host"
        Write-Error "Error creating table Host"
        Exit 12
    }

# insert data into table

WrtLog -text "Adding data to Host..."
ForEach ($row in $ImportCSV)
    {
        $CsvRecSrvr = $row."Server address"
        $CsvRecHost = $row."Host Name"
        $CsvRecOS = $row."OS name"
        $CsvRecVer = $row."OS Version"
        $CsvRecCpu = $row."CPU count"
        $CsvRecMem = $row.Memory
        $CsvRecDNet = $row."DotNet version"
        $SqlIns = @"
                USE Hostinfo
                INSERT INTO Host ('Server address', 'Host name', 'OS name','OS version', 'CPU count', 'Memory, 'DotNet version')
                VALUES('$CsvRecSrvr', '$CsvRecHost', '$CsvRecOS', '$CsvRecVer' ,'$CsvRecCpu','$CsvRecMem', '$CsvRecDnet');
"@
        SqlQry -Qry $SqlIns
    }
WrtLog -text "OK"

# End of script timestamp

$FinishTime = Get-Date
WrtLog "End of script time `n$FinishTime"
