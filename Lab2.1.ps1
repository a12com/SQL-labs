Import-Module SqlServer

# Create credentials
$UsrName = "SA"
Write-Output "Enter $UsrName password"
$Pwd = Read-host -AsSecureString
$SACred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UsrName, $Pwd
$SvrName = "lon-svr1"
$SysCred = Get-Credential "Adatum\Administrator"

# Create Exitcode function

function ExitWithCode 
    {
        param ($exitcode)

        $host.SetShouldExit($exitcode) 
        exit 
    }

# Create pssession to work with remote server

$PsOps = New-PSSessionOption -OpenTimeout 30 -CancelTimeout 30 -OperationTimeout 30
$PSS = New-PSSession -ComputerName $SvrName -Credential $SysCred -SessionOption $PsOps

If ($Pss -eq $null)
    {   
        Write-Host "Could not establish connection to $SvrName. Script aborted" -ForegroundColor Yellow
        ExitWithCode
    }

# SQL Query function
Function SqlQry 
    {
        Param([string]$Qry, [string]$ServerInstance=$SvrName, $Credential)
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


#Invoke-Command -ComputerName $SvrName -Credential $SysCred -ScriptBlock {New-NetFirewallRule -DisplayName "RPC allow" -Direction Inbound -Protocol Tcp -LocalPort 135, 2101, 2103, 2015  

# get free space info

Try
    {
        $FsC = Invoke-Command -Session $PSS -ScriptBlock {get-WmiObject -class win32_logicaldisk -Filter "DeviceID='C:'"}
    }
Catch 
    {
        Write-Host "Could not get information about disk C space on $SvrName. Script is still running" -ForegroundColor Yellow
        ExitWithCode 
    }

Try
    {
        $FsE = Invoke-Command -Session $PSS -ScriptBlock {get-WmiObject -class win32_logicaldisk -Filter "DeviceID='E:'"}
    }
Catch 
    {
        Write-Host "Could not get information about disk E space on $SvrName. Script aborted" -ForegroundColor Yellow
        ExitWithCode
    }
Try
    {
        $FsF = Invoke-Command -Session $PSS -ScriptBlock {get-WmiObject -class win32_logicaldisk -Filter "DeviceID='F:'"}
    }
Catch 
    {
        Write-Host "Could not get information about disk F space on $SvrName. Script aborted" -ForegroundColor Yellow
        ExitWithCode 
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
        Exit
    }

If ($fsF.FreeSpace -lt 20) 
    {
        Write-Host "Disk F has only $([Math]::Round(($FsF.Freespace / 1mb),2)) Mb free. Please free up space and restart" -ForegroundColor Yellow
        Write-Error "Not enough space on disk to continue"
        Exit
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
                Exit
            }
        $ChkFileDB = Invoke-Command -Session $PSS -ScriptBlock {Test-Path "F:\MSSQL\MSSQLSERVER\tempdb.mdf"}
        if ($ChkFileDB)
            {
                Write-Host 'F:\MSSQL\MSSQLSERVER\tempdb.mdf already exists. Remove file and then restart!'  -ForegroundColor Yellow
                Write-Error "F:\MSSQL\MSSQLSERVER\tempdb.mdf already exists. Remove file and then restart!"
                Exit
            }
    }
Catch 
    {
        Write-Host "Could not get information about file locations. Script aborted" -ForegroundColor Yellow
        ExitWithCode
    }

# create new folders

Try
    {
        Invoke-Command -Session $PSS -ScriptBlock {New-Item -Path E:\MSSQL\MSSQLSERVER -ItemType Directory -Force}
    }
Catch 
    {
        Write-Host "Could not create E:\MSSSQL\MSSQLSERVER folder on $SvrName. Script aborted" -ForegroundColor Yellow
        ExitWithCode 
    }

Try
    {
        Invoke-Command -Session $PSS -ScriptBlock {New-Item -Path F:\MSSQL\MSSQLSERVER -ItemType Directory -Force}
    }
Catch 
    {
        Write-Host "Could not create F:\MSSSQL\MSSQLSERVER folder on $SvrName. Script aborted" -ForegroundColor Yellow
        ExitWithCode
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
        ExitWithCode
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
