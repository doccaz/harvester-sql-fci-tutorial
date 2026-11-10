# Connects to SQLFCI every ~0.5 s for $dur seconds, logging time + serving host. Placeholder DUR replaced by caller.
$dur = DURSEC
$end = (Get-Date).AddSeconds($dur)
$sw = [Diagnostics.Stopwatch]::StartNew()
while ((Get-Date) -lt $end) {
  $t = (Get-Date).ToString('HH:mm:ss.fff'); $res = 'FAIL'
  try {
    $c = New-Object System.Data.SqlClient.SqlConnection 'Server=SQLFCI;Database=master;Integrated Security=SSPI;Connect Timeout=2;Pooling=false'
    $c.Open(); $q = $c.CreateCommand(); $q.CommandText = "select cast(SERVERPROPERTY('ComputerNamePhysicalNetBIOS') as nvarchar(50))"; $res = 'OK ' + $q.ExecuteScalar(); $c.Close()
  } catch { }
  "$t $res"
  Start-Sleep -Milliseconds 400
}
