$c = New-Object System.Data.SqlClient.SqlConnection 'Server=SQLFCI;Database=master;Integrated Security=SSPI;Connect Timeout=5'
$c.Open(); $q = $c.CreateCommand()
$q.CommandText = "select cast(@@servername as nvarchar(60)) + ' | clustered=' + cast(SERVERPROPERTY('IsClustered') as varchar) + ' | on ' + cast(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') as varchar) + ' | ' + left(@@version,40)"
$q.ExecuteScalar(); $c.Close()
