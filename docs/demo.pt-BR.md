# Demo: SQL Server 2016 FCI no Harvester v1.9.0 com discos compartilhados SCSI-3 PR

SOMENTE LABORATÓRIO. Senhas descartáveis do `env.example`: troque-as se o lab for acessível fora da sua rede. O procedimento genérico está em `shared-pr-disks.md`.

## Inventário do lab (namespace `labs`)

| VM | IP | Host | Função |
|---|---|---|---|
| sqllab-dc1 | 192.168.100.170 | node-a | Controlador de domínio `sqllab.local`, share de witness, cliente da sonda |
| sqllab-fci-n1 | 192.168.100.171 | node-a | Nó 1 do cluster |
| sqllab-fci-n2 | 192.168.100.172 | node-b | Nó 2 do cluster |
| (cluster `sqllab-wsfc`) | 192.168.100.173 | | Nome do cluster |
| (instância SQL `SQLFCI`) | 192.168.100.174 | | SQL Server em cluster, instância padrão, TCP 1433 |

LUNs compartilhadas (PVs RWX Block, `lun` + `reservation: true`): `fci-quorum`, `fci-sqldata` (E:), `fci-sqllog` (F:).

## Contas (login no console)

| Conta | Senha | Onde |
|---|---|---|
| `SQLLAB\Administrator` | `Sqllab2026` | Admin do domínio. Use nas três VMs |
| `Administrator` (local) | `Sqllab2026` | Conta local em n1/n2 (só se não estiver logado como usuário do domínio) |
| `SQLLAB\sqlsvc` | `Sqllab2026` | Conta de serviço do SQL; ninguém faz login com ela |
| `SQLLAB\SQLAdmins` | n/a | Grupo com sysadmin na instância |

Login no console: escolha "Outro usuário" e digite `SQLLAB\Administrator`.
Senha DSRM: `Sqllab2026` (só usada no modo de recuperação do AD).

## Roteiro da demo (cerca de 15 minutos)

### 1. Mostrar como os discos são ligados (lado Harvester, 2 min)
```bash
kubectl -n labs get pvc fci-quorum fci-sqldata fci-sqllog        # RWX, Block
kubectl -n labs get vm sqllab-fci-n1 -o yaml | grep -B2 -A6 'lun:'  # shareable, errorPolicy: report, lun/scsi/reservation
pod=$(kubectl -n labs get pods -l vm.kubevirt.io/name=sqllab-fci-n1 -o name | tail -1)
kubectl -n labs exec $pod -c compute -- virsh --connect 'qemu+unix:///session?socket=/var/run/libvirt/virtqemud-sock' \
  dumpxml labs_sqllab-fci-n1 | grep -E "device='lun'|pr-helper"
```
Pontos a destacar: o disco de boot é VirtIO; os discos compartilhados são `lun` no barramento SCSI; as duas VMs ficam
em hosts diferentes; a UI do v1.9.0 não consegue definir `lun`, então essa parte é feita em YAML.

### 2. Mostrar o cluster (console do n1, 2 min)
Gerenciador de Cluster de Failover > Funções: `SQL Server (MSSQLSERVER)`, nó proprietário, discos Online, share de witness.
Ou via PowerShell:
```powershell
Get-ClusterNode | ft Name,State
Get-ClusterGroup | ft Name,OwnerNode,State
Get-ClusterResource | ft Name,ResourceType,State
```

### 3. Mostrar o resultado da validação SCSI-3 PR (2 min, no n1)
NÃO rode `Test-Cluster -Include Storage` agora: os discos pertencem à função do SQL, então todos os testes de storage
aparecem como "Not Applicable". Abra o relatório salvo que passou (gerado antes de instalar o SQL):
```powershell
Start-Process msedge 'C:\Windows\Cluster\Reports\PR-validation-PASS.htm'
```
Mostre Storage: "Validate SCSI-3 Persistent Reservation" e "Validate Disk Failover" = Success. (a falha com o driver VMDP público está descrita em shared-pr-disks.md.) Rodar de novo ao vivo exige a função do SQL offline e os
discos de volta em Available Storage: evite numa demo.

### 4. Iniciar a sonda de cliente (console do DC, deixar visível)
Versão mínima equivalente ao `vm\probe.ps1`:
```powershell
while($true){ $t=Get-Date -f HH:mm:ss.fff
  try{ $c=New-Object Data.SqlClient.SqlConnection 'Server=SQLFCI;Integrated Security=SSPI;Connect Timeout=2'
       $c.Open(); $q=$c.CreateCommand(); $q.CommandText='select @@servername+'' on ''+cast(serverproperty(''ComputerNamePhysicalNetBIOS'') as varchar)'
       "$t OK   $($q.ExecuteScalar())"; $c.Close() } catch { "$t FAIL" }
  Start-Sleep -Milliseconds 400 }
```

### 5. Failover planejado (~15-50 s de indisponibilidade)
No n1 ou n2:
```powershell
Move-ClusterGroup -Name 'SQL Server (MSSQLSERVER)'
```
Observe a sonda mostrar FAIL por 15 a 50 s e depois OK a partir do outro nó.

### 6. Falha abrupta (~35-50 s de indisponibilidade)
Escolha uma:
- UI do Harvester: VM proprietária > Force Stop. A função vai para o outro nó. A VM parada pode NÃO reiniciar
  sozinha (harvester#11835); inicie manualmente.
- Ou mate o QEMU no host (`kill -9` do processo `qemu-system` do virt-launcher dessa VM). A VM reinicia automaticamente.
O nó sobrevivente assume a reserva (fencing) e o SQL sobe nele. Se alguém perguntar por que demora tanto,
veja "Para onde vai o tempo do failover" abaixo.

### 7. Mostrar que os dados sobreviveram
```powershell
sqlcmd -S SQLFCI -E -Q "select name from sys.databases"
```
(Se o `sqlcmd` não existir, use o trecho da sonda com outra consulta.) Limpeza: o banco `fcitest` dos testes pode ser removido.

## Como a validação SCSI-3 PR foi executada (se alguém perguntar)

Feita uma vez, ANTES de instalar o SQL (depois disso os discos pertencem à função do SQL e os testes aparecem como "Not Applicable").

Pré-condições:
- Os dois nós no domínio e em cluster (`sqllab-wsfc`); discos compartilhados anexados como `lun` + `reservation: true`.
- As três LUNs online e inicializadas em GPT em um nó (senão o `Test-Cluster` encontra "No disks").
- Driver `vioscsi` do virtio-win upstream nos dois nós (o `pvvxscsi` do VMDP falha no teste de PR).
- Só no lab: `/etc/target/pr` presente no nó do LIO, senão todo REGISTER dá erro e o teste falha.

Comando (PowerShell elevado no n1, admin do domínio; cerca de 5 minutos; o relatório vai para `C:\Windows\Cluster\Reports\`):
```powershell
Test-Cluster -Node sqllab-fci-n1,sqllab-fci-n2 -Include Storage -ReportName C:\Windows\Cluster\Reports\PR-validation-<data>
```
O teste de PR registra e reserva um disco a partir de um nó e verifica que o outro nó é recusado com
RESERVATION CONFLICT, o que prova que as reservas chegam ao storage. Resultado: todos os testes de Storage verdes
(`PR-validation-<data>.htm`, copiado para `PR-validation-PASS.htm`; o passo 08 também salva uma cópia em `runbook/reports/`).

## Para onde vai o tempo do failover (se alguém perguntar)

O storage não é a parte lenta. Detalhamento de um movimento planejado e de um `kill -9`, a partir do log do cluster
no nó sobrevivente (segundos, arredondados; a sonda tem só cerca de 2 s de resolução, então as linhas somam o total com folga de arredondamento):

| Fase | Planejado (16,8 s de indisponibilidade) | `kill -9` (40,2 s de indisponibilidade) |
|---|---|---|
| Espera o timeout dos heartbeats | nenhuma | 21,4 |
| Transferência para o nó sobrevivente | 1,2 | 6,3 |
| Discos online (assume a reserva SCSI-3 PR; em paralelo com o IP) | 0,2 | 0,2 |
| Endereço IP do SQL online | 3,7 | 3,7 |
| Nome de rede do SQL online | 6,1 | 6,2 |
| SQL Server sobe, até a sonda conectar | 5,7 | 2,7 |

- **Falhas abruptas esperam o heartbeat.** `Get-Cluster | fl SameSubnetDelay,SameSubnetThreshold` mostra 1000 ms x 20,
  então um nó morto só é declarado depois de 20 s de heartbeats perdidos. O movimento planejado pula essa espera. O Force Stop se comporta como o `kill -9`.
- **Os discos levam cerca de 0,2 s.** Assumir a reserva no target LIO é rápido. As réplicas do Longhorn não participam:
  matar uma VM não mexe no pod do LIO que serve as LUNs.
- **O IP e o nome de rede custam cerca de 10 s** em todos os casos. A causa não foi investigada (provavelmente a detecção de
  endereço duplicado e o registro no AD/DNS, sem confirmação).
- **Sem explicação:** por que os movimentos planejados levaram de 16 a 51 s entre os builds. Os logs dos mais lentos não foram guardados.

Para ver na sua própria execução, no nó sobrevivente logo depois do teste (`-TimeSpan` é em minutos):
```powershell
Get-ClusterLog -Node $env:COMPUTERNAME -Destination C:\Windows\Temp -TimeSpan 15 -UseLocalTime
Select-String -Path C:\Windows\Temp\*_cluster.log -Pattern 'has transitioned from state' | % Line
```
Um `(Get-Cluster).SameSubnetThreshold` menor (digamos 5 a 10) deve encurtar os casos de falha abrupta, ao custo de mais
failovers falsos. Não testado aqui.

## Pontos de conversa / limites
- VMs com discos PR não fazem live migration: manutenção de nó = failover do cluster convidado e depois desligar a VM.
- Um upgrade do Harvester reverte o feature gate e o override do pr-helper: rode `harvester-pr disable --apply` antes e reaplique depois.
- Exige um SAN com SCSI-3 PR (Longhorn/Ceph/NFS não servem). Aqui um target Linux LIO sobre Longhorn faz o papel do SAN
  (só no lab: precisa de `/etc/target/pr` no nó dele, aplicado pelo CloudInit CR `lio-san-aptpl-dir`).
- O Windows precisa do driver `vioscsi` do virtio-win upstream nas LUNs compartilhadas; o `pvvxscsi` público do VMDP falha no teste de PR.
- Não testado: multipath no caminho de dados, um SAN real, mais de dois nós.

## Reiniciando o lab entre demos
Mova a função de volta ao n1 (`Move-ClusterGroup -Name 'SQL Server (MSSQLSERVER)' -Node sqllab-fci-n1`), confirme que as duas
VMs estão rodando e que `Get-ClusterNode` mostra ambos Up.
