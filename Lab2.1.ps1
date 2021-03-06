<#Script it using PowerShell:
Code should be wrapped in PowerShell script, started from student local PC, Password isn’t provided as a plain text, errors capturing is active, code returns DB files locations before execution and after, check the existing files with the same name in the target location, and check free space on disk. To check DB with TSQL:
SELECT name, physical_name,size,max_size,growth  
FROM sys.master_files  
WHERE database_id = DB_ID(N'tempdb'); 
#>


Import-Module SqlServer

# Create credentials
$UsrName = "SA"
Write-Output "Enter $UsrName password"
$Pwd = Read-host -AsSecureString
$SACred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UsrName, $Pwd
$SvrName = "lon-svr1"
$SysCred = Get-Credential "Adatum\Administrator"

# Create pssession to work with remote server

$PsOps = New-PSSessionOption -OpenTimeout 30 -CancelTimeout 30 -OperationTimeout 30
$PSS = New-PSSession -ComputerName $SvrName -Credential $SysCred -SessionOption $PsOps

If ($PSS -eq $null)
    {   
        Write-Host "Could not establish connection to $SvrName. Script aborted" -ForegroundColor Yellow
        Exit 14
    }

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
                WrtLog -text "$Exc"
            }

        # Check if there is a more exacting Error code in Inner Exception
        If ($Err.exception.InnerException -ne $NULL)
            {
                $InnExc=$Err.Exception.InnerException
                WrtLog -text "$InnExc"
            }

        # If No InnerException or Exception has been identified
        # Use GetBaseException Method to retrieve object
        if ($Exc -eq '' -and $InnExc -eq '')
            {
                $Exc=$Err.GetBaseException()
                WrtLog -text "$Exc"
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
                Invoke-SqlCmd -ServerInstance $SvrIns -Credential $Credential -Query $Qry -QueryTimeout 0
                Start-Sleep -Milliseconds 1500
            }
        Catch
            {
                ExitWithCode -exitcode 10
            }
    }


#Invoke-Command -ComputerName $SvrName -Credential $SysCred -ScriptBlock {New-NetFirewallRule -DisplayName "RPC allow" -Direction Inbound -Protocol Tcp -LocalPort 135, 2101, 2103, 2015  

# get free space info

$FsC = Invoke-Command -Session $PSS -ScriptBlock {get-WmiObject -class win32_logicaldisk -Filter "DeviceID='C:'"} -ErrorAction SilentlyContinue

Try
    {
        $FsE = Invoke-Command -Session $PSS -ScriptBlock {get-WmiObject -class win32_logicaldisk -Filter "DeviceID='E:'"}
    }
Catch 
    {
        Write-Host "Could not get information about disk E space on $SvrName. Script aborted" -ForegroundColor Yellow
        ExitWithCode -exitcode 17
    }
Try
    {
        $FsF = Invoke-Command -Session $PSS -ScriptBlock {get-WmiObject -class win32_logicaldisk -Filter "DeviceID='F:'"}
    }
Catch 
    {
        Write-Host "Could not get information about disk F space on $SvrName. Script aborted" -ForegroundColor Yellow
        ExitWithCode -exitcode 18
    }

Write-Host "Free Space on Server $SvrName at the moment is:" -ForegroundColor Green
Write-Host "Disk C:`t`t$([Math]::Round(($FsC.Freespace / 1mb),2)) Mb"
Write-Host "Disk E:`t`t$([Math]::Round(($FsE.Freespace / 1mb),2)) Mb"
Write-Host "Disk F:`t`t$([Math]::Round(($FsF.Freespace / 1mb),2)) Mb"

# check if it's enough free space on E & F

If ($FsE.FreeSpace -lt 20)
    {
        Write-Host "Disk E has only $([Math]::Round(($FsE.Freespace / 1mb),2)) Mb free. Please free up space and restart" -ForegroundColor Yellow
        Write-Error "Not enough space on disk to continue"
        Exit 20
    }

If ($fsF.FreeSpace -lt 20) 
    {
        Write-Host "Disk F has only $([Math]::Round(($FsF.Freespace / 1mb),2)) Mb free. Please free up space and restart" -ForegroundColor Yellow
        Write-Error "Not enough space on disk to continue"
        Exit 21
    }

# Output current file path

Write-Host "Files paths before change was:" -ForegroundColor Green
SqlQry -Qry 'USE Tempdb SELECT physical_name "File location" FROM sys.database_files'

# Check files existence

Try
    {
        $ChkFileLOG = Invoke-Command -Session $PSS -ScriptBlock {Test-Path "E:\MSSQL\MSSQLSERVER\templog.ldf"}
        If ($ChkFileLOG)
            {        
                Write-Host 'E:\MSSQL\MSSQLSERVER\templog.ldf already exists. Remove file and then restart!'  -ForegroundColor Yellow
                Write-Error "E:\MSSQL\MSSQLSERVER\templog.ldf already exists. Remove file and then restart!"
                Exit 8
            }
        $ChkFileDB = Invoke-Command -Session $PSS -ScriptBlock {Test-Path "F:\MSSQL\MSSQLSERVER\tempdb.mdf"}
        if ($ChkFileDB)
            {
                Write-Host 'F:\MSSQL\MSSQLSERVER\tempdb.mdf already exists. Remove file and then restart!'  -ForegroundColor Yellow
                Write-Error "F:\MSSQL\MSSQLSERVER\tempdb.mdf already exists. Remove file and then restart!"
                Exit 9
            }
    }
Catch 
    {
        Write-Host "Could not get information about file locations. Script aborted" -ForegroundColor Yellow
        ExitWithCode -exitcode 19
    }

# create new folders

Try
    {
        Invoke-Command -Session $PSS -ScriptBlock {New-Item -Path E:\MSSQL\MSSQLSERVER -ItemType Directory -Force}
    }
Catch 
    {
        Write-Host "Could not create E:\MSSSQL\MSSQLSERVER folder on $SvrName. Script aborted" -ForegroundColor Yellow
        ExitWithCode -exitcode 24
    }

Try
    {
        Invoke-Command -Session $PSS -ScriptBlock {New-Item -Path F:\MSSQL\MSSQLSERVER -ItemType Directory -Force}
    }
Catch 
    {
        Write-Host "Could not create F:\MSSSQL\MSSQLSERVER folder on $SvrName. Script aborted" -ForegroundColor Yellow
        ExitWithCode -exitcode 25
    }

# change tempdb files size, growth and path

SqlQry -Qry "ALTER DATABASE [tempdb] MODIFY FILE ( NAME = tempdev, SIZE = 10 MB, FILEGROWTH = 10 MB )" 
SqlQry -Qry "ALTER DATABASE [tempdb] MODIFY FILE ( NAME = templog, SIZE = 10 MB, FILEGROWTH = 1 MB )"
SqlQry -Qry "ALTER DATABASE tempdb MODIFY FILE ( NAME = tempdev, FILENAME = 'F:\MSSQL\MSSQLSERVER\tempdb.mdf' )"
SqlQry -Qry "ALTER DATABASE tempdb MODIFY FILE ( NAME = templog, FILENAME = 'E:\MSSQL\MSSQLSERVER\templog.ldf' )"

# safe shutdown SQL engine service

Write-Host "Quering SQL engine service shutdown" -ForegroundColor Red
SqlQry -Qry "Shutdown"
Start-Sleep -Seconds 1

# re-start SQL engine service after shutdown

$SqlState = Invoke-Command -Session $PSS -ScriptBlock {Get-Service -name "MSSQLSERVER"}

while ($SqlState.Status -ne "Stopped")
    {
        Write-Host "SQL Engine is still shutting down. Waiting for complete"
        Start-Sleep -Milliseconds 5000
        $SqlState = Invoke-Command -Session $PSS -ScriptBlock {Get-Service -name "MSSQLSERVER"}   
    }

try 
    {
        Invoke-Command -Session $PSS -ScriptBlock {Start-Service -name "MSSQLSERVER"}
        Start-Sleep -Seconds 10
    }
Catch 
    {
        Write-Host "Error starting SQL enginge service (MSSQLSERVER)"  -ForegroundColor Yellow
        ExitWithCode -exitcode 30
    }

# check if server started properly

$SqlState = Invoke-Command -Session $PSS -ScriptBlock {Get-Service -name "MSSQLSERVER"}

while ($SqlState.Status -ne "running")
    {
        Write-Host "SQL Engine is still starting up. Waiting for complete"
        Start-Sleep -Milliseconds 5000
        $SqlState = Invoke-Command -Session $PSS -ScriptBlock {Get-Service -name "MSSQLSERVER"}   
    }

# Output current file path

Write-Host "SQL engine service started" -ForegroundColor Blue
Write-Host "Files paths at the moment are:" -ForegroundColor Green
SqlQry -Qry 'USE Tempdb SELECT physical_name "File location" FROM sys.database_files'
#SqlQry -Qry 'SELECT @@SERVERNAME; SELECT @@VERSION'
