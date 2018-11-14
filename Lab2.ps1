Import-Module SqlServer

# Create credentials
$UsrName = "SA"
Write-Output "Enter $UsrName password"
$Pwd = Read-host -AsSecureString
$SACred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UsrName, $Pwd
$SvrName = "lon-svr1"
$SysCred = Get-Credential "Adatum\Administrator"
<#
# create sql connection object
$SQLServer = $SvrName #use Server\Instance for named SQL instances!
$SQLDBName = "testdb"
$SqlConnection = New-Object System.Data.SqlClient.SqlConnection
$SqlConnection.ConnectionString = "Server = $SQLServer; User ID= 'SA'; Password= $pwd" 
$SqlCmd = New-Object System.Data.SqlClient.SqlCommand
$SqlCmd.CommandText = 'SELECT @@Servername'
$SqlCmd.Connection = $SqlConnection 
$SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
$SqlAdapter.SelectCommand = $SqlCmd 
$DataSet = New-Object System.Data.DataSet
$SqlAdapter.Fill($DataSet) 
$SqlConnection.Close()
#>
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
            Write-Host $_.Exception.Message 
            Write-Host $_.Exception.Itemname
            Break
        }
    }

# change tempdb files size & growth

SqlQry -Qry "ALTER DATABASE [tempdb] MODIFY FILE ( NAME = tempdev, SIZE = 10 MB, FILEGROWTH = 10 MB )" 

SqlQry -Qry "ALTER DATABASE [tempdb] MODIFY FILE ( NAME = templog, SIZE = 10 MB, FILEGROWTH = 1 MB )"

# Output current free space & check if it's enough free space on E & F

$fstotal = SqlQry -Qry "EXEC MASTER..xp_fixeddrives"
Write-Host "Total free space on server was" -ForegroundColor Green
Write-Output $fstotal
$fsE = ($fstotal | Where-Object -Property Drive -eq "E")."MB free"
$fsF = ($fstotal | Where-Object -Property Drive -eq "F")."MB free"
# REALLY STRANGE BEHAVIOR HERE ASK FOR HELP!!!!!
Start-Sleep -Milliseconds 1500 
# REALLY STRANGE BEHAVIOR HERE ASK FOR HELP!!!!!
If ($fsE -lt 20) 
    {
        Write-Output "Disk E has only $fstotalE Mb free. Please free up space and restart"
        Break
    }

If ($fsF -lt 20) 
    {
        Write-Output "Disk F has only $fstotalF Mb free. Please free up space and restart"
        Break
    }

# Output current file path

Write-Host "Files paths before change was:" -ForegroundColor yellow
SqlQry -Qry 'USE Tempdb SELECT physical_name "File location" FROM sys.database_files'

# check if tempDB.mdf file already exists and set new filepath
$ChkFile = SqlQry -Qry "EXEC master.dbo.xp_fileexist 'F:\MSSQL\MSSQLSERVER\tempdb.mdf'"
$ChkDir = $ChkFile."Parent Directory Exists"
$ChkFile = $ChkFile."File Exists"

If ($ChkFile)
    {
        Write-Output 'F:\MSSQL\MSSQLSERVER\tempdb.mdf already exists. Remove file and then restart!'
        Break
    }

If (!$ChkDir)
    {
        SqlQry -Qry 'EXEC master.dbo.xp_create_subdir "F:\MSSQL\MSSQLSERVER\"'    
    }

SqlQry -Qry "ALTER DATABASE tempdb MODIFY FILE ( NAME = tempdev, FILENAME = 'F:\MSSQL\MSSQLSERVER\tempdb.mdf' )"


# check if tempLOG.ldf file already exists and set new filepath
$ChkFile = SqlQry -Qry "EXEC master.dbo.xp_fileexist 'E:\MSSQL\MSSQLSERVER\templog.ldf'"
$ChkDir = $ChkFile."Parent Directory Exists"
$ChkFile = $ChkFile."File Exists"

If ($ChckFile)
    {
        Write-Output 'E:\MSSQL\MSSQLSERVER\templog.ldf already exists. Remove file and then restart!'
        Break
    }

If (!$ChkDir)
    {
        SqlQry -Qry 'EXEC master.dbo.xp_create_subdir "E:\MSSQL\MSSQLSERVER\"'    
    }

SqlQry -Qry "ALTER DATABASE tempdb MODIFY FILE ( NAME = templog, FILENAME = 'E:\MSSQL\MSSQLSERVER\templog.ldf' )"

# safe shutdown of SQL engine service

Write-Host "Quering server shutdown" -ForegroundColor Red
SqlQry -Qry "Shutdown"

<#
# Create PSDrive to SQL Server with authentication
$Root = 'SQLSERVER:\SQL\lon-svr1\MSSQLSERVER'
New-PSDrive -Name SqlDrv -PSProvider SqlServer -Root $Root -Credential $SysCred   
Set-Location SqlDrv:
$Wmi = (get-item .).ManagedComputer
$DefaultSqlInstance = $Wmi.Services['MSSQLSERVER'] 

Get-SqlInstance -Credential $SqlCred -ServerInstance $SvrName 
Stop-SqlInstance -Credential $SqlCred -ServerInstance $SvrName
Start-SqlInstance -Credential $CredSA#>

# re-start SQL engine service after shutdown

$SqlStat = Invoke-Command -ComputerName $SvrName -Credential $SysCred -ScriptBlock {Get-Service -name "MSSQLSERVER"}

while ($SqlStat.Status -ne "Stopped")
    {
        Start-Sleep -Milliseconds 1500
        $SqlStat = Invoke-Command -ComputerName $SvrName -Credential $SysCred -ScriptBlock {Get-Service -name "MSSQLSERVER"}   
    }

Invoke-Command -ComputerName $SvrName -Credential $SysCred -ScriptBlock {Start-Service -name "MSSQLSERVER"}

# Output new file path & free disk space

Write-Host "Files paths after change is" -ForegroundColor Yellow
SqlQry -Qry 'USE Tempdb SELECT physical_name "File location" FROM sys.database_files'
Write-Host "Total free space on server is" -ForegroundColor Green
SqlQry -Qry "EXEC MASTER..xp_fixeddrives"

