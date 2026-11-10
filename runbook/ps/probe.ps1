# Client probe: connect to SQLFCI every ~0.4 s for DURSEC seconds; log time + serving node.
$end = (Get-Date).AddSeconds(DURSEC)
while ((Get-Date) -lt $end) {
  $t = (Get-Date).ToString('HH:mm:ss.fff'); $res = 'FAIL'
  try {
    $c = New-Object System.Data.SqlClient.SqlConnection 'Server=SQLFCI;Database=master;Integrated Security=SSPI;Connect Timeout=2;Pooling=false'
    $c.Open(); $q = $c.CreateCommand(); $q.CommandText = "select cast(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') as nvarchar(50))"; $res = 'OK ' + $q.ExecuteScalar(); $c.Close()
  } catch { }
  "$t $res"
  Start-Sleep -Milliseconds 400
}
