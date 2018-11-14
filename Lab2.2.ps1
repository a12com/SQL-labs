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

# SQL Query function
Function SqlQry 
    {
        Param([string]$Qry, [string]$ServerInstance=$SvrName, $Credential=$SACred)
        Try
            {
                Invoke-SqlCmd -ServerInstance $ServerInstance -Credential $Credential -Query $Qry -QueryTimeout 0
                Start-Sleep -Milliseconds 1500
            }
        Catch
            {
                ExitWithCode
            }
    }

# Add SMO assemblies
<#
add-type -AssemblyName "Microsoft.SqlServer.ConnectionInfo, Version=11.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop

add-type -AssemblyName "Microsoft.SqlServer.Smo, Version=11.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop

add-type -AssemblyName "Microsoft.SqlServer.SMOExtended, Version=11.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop

add-type -AssemblyName "Microsoft.SqlServer.SqlEnum, Version=11.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop

add-type -AssemblyName "Microsoft.SqlServer.Management.Sdk.Sfc, Version=11.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91" -ErrorAction Stop #>

# This function determines whether a database exists in the system.
Function IsDBExists
    {
        Param([string]$ServerInstance=$SvrName, $Credentials=$SACred, [string]$DBName)
    
            $exists = $FALSE
            try
                {
                    $ChkDbExist = Get-SqlDatabase -ServerInstance $ServerInstance -Credential $Credentials -Name "$DBName"
                    $exists = ($ChkDbExist -ne $null)
                }
            catch
                {
                    Write-Error "Failed to connect to DB $DBName on $ServerInstance"
                }
 
            Write-Output $exists
    }


IsDBExists -DBName "tempdb"
$query = @"
    USE master;  
    GO
"@
SqlQry -Qry $query

# Check DB HumanResources for existence. If exists delete.

Write-Host "Checking DB HumanResources for existence"
$ChkDb = IsDBExists -DBName "HumanResources"
    if ($ChkDb)
        {
            Write-Host "DB HumanResources exists. Trying to delete."
            $query = @"
                IF DB_ID (N'HumanResources') IS NOT NULL
                DROP DATABASE HumanResources;
                GO
"@
            Write-Host "DB Deleted"
        }

    else 
        {
            Write-Host "DB HumanResources does not exists."
        }

# Check DB files existense (E:\Data\HumanResources.mdf)

$ChkFile = SqlQry -Qry "EXEC master.dbo.xp_fileexist 'E:\Data\HumanResources.mdf';"
$ChkDir = $ChkFile."Parent Directory Exists"
$ChkFile = $ChkFile."File Exists"

If ($ChkFile)
    {
        Write-Error 'E:\Data\HumanResources.mdf already exists. Remove file and then restart!'
        Exit
    }

If (!$ChkDir)
    {
        SqlQry -Qry 'EXEC master.dbo.xp_create_subdir "E:\Data";'    
    }


# Check DB files existense (E:\Logs\HumanResources.ldf)
$ChkFile = SqlQry -Qry "EXEC master.dbo.xp_fileexist 'E:\Logs\HumanResources.ldf'"
$ChkDir = $ChkFile."Parent Directory Exists"
$ChkFile = $ChkFile."File Exists"

If ($ChckFile)
    {
        Write-Error 'E:\Logs\HumanResources.ldf already exists. Remove file and then restart!'
        Exit
    }

If (!$ChkDir)
    {
        SqlQry -Qry 'EXEC master.dbo.xp_create_subdir "E:\Logs";'    
    }

# Create DB HumanResources

$query = @"
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
GO    
"@
SqlQry -Qry $query

# Check DB files
$query = @"
    SELECT name, physical_name,size * 8 / 1024 'Size MB' ,max_size,growth * 8 / 1024 'Growth MB'
    FROM sys.master_files  
    WHERE database_id = DB_ID(N'HumanResources'); 
"@
$ChkDb = SqlQry -Qry $query
If ($ChkDb -ne $null)
    {
        Write-Host "$ChkDb"
    }
else 
    {
        Write-Error "Error creation DB HumanResources"
        Exit 
    }