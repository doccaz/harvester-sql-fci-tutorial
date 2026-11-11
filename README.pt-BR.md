# SQL Server 2016 Failover Cluster Instance no Harvester com discos `lun` compartilhados nativos (SCSI-3 PR)

Tutorial de laboratório: monta um cluster de duas VMs Windows Server 2022 / SQL Server 2016 SP2 (**FCI**) no **Harvester v1.9.0**, usando discos `lun` do KubeVirt com reservas persistentes SCSI-3 como armazenamento compartilhado, e executa testes de failover.

> **Somente laboratório.** Mídia de avaliação, senhas descartáveis (`Sqllab2026`, definidas em `env.example`), sem hardening e com o Windows Update desligado. Não use como modelo de produção.
> English: see [README.md](README.md). Os scripts e a maior parte da documentação estão em inglês.

## Resumo

**Você precisa de:**
- Harvester **v1.9.0** com 2 ou mais nós agendáveis.
- Armazenamento compartilhado com reservas persistentes SCSI-3. Longhorn, Ceph e NFS não servem para esses discos. O tutorial usa um pod iSCSI Linux LIO como substituto; uma SAN real não foi testada.
- Três ISOs: Windows Server 2022 de avaliação, SQL Server 2016 SP2 e virtio-win.
- Uma rede de VM na sua LAN com 5 IPs estáticos livres.

**Depois:**
1. `cp env.example env.local` e ajuste o kubeconfig, os nomes dos nós, os IPs e a rede.
2. `./harvester-pr enable --apply` liga o feature gate PersistentReservation.
3. Construa a imagem dourada do Windows ([docs/golden-image.md](docs/golden-image.md), cerca de 25 minutos, uma vez).
4. `runbook/run-all.sh` (cerca de 1,5 hora). Ele pausa uma vez para um comando SSH manual no `NODE_A`, necessário só para o substituto LIO.
5. `runbook/11-failover-tests.sh planned | stop --yes | kill --yes` mede os failovers.

Os detalhes de cada passo estão em [Início rápido](#início-rápido).

## O que você obtém

| Componente | Detalhe |
|---|---|
| 3 VMs Windows | `sqllab-dc1` (controlador de domínio + share de witness), `sqllab-fci-n1` e `sqllab-fci-n2` (nós do cluster, em hosts Harvester diferentes) |
| Armazenamento compartilhado | 3 PVCs Block RWX (quorum 1 GiB, dados 4 GiB, log 2 GiB) anexados como `lun` + `reservation: true`, servidos por um alvo iSCSI Linux LIO que faz o papel de SAN |
| Resultado | A validação de armazenamento passa (SCSI-3 PR + Disk Failover) e a FCI do SQL sobe nos dois nós. Indisponibilidade medida em vários builds completos: failover planejado 16-51 s, Force Stop 33-42 s, `kill -9` do QEMU 40-52 s. Varia de execução para execução: planeje uma demonstração em torno de um minuto |

## Arquitetura

```
 sua estação                              cluster Harvester v1.9.0 (2+ nós, Longhorn)
 -----------                              -------------------------------------------------------------
 kubectl / helm / virtctl                 NODE_A                                  NODE_B
 scripts do runbook --- kubectl ------->    |  alvo iSCSI Linux LIO (pod)           |  servidor de ISOs (pod nginx, :8099)
      |                                     |  = a "SAN", exporta 3 LUNs            |
      |                                     |        ^ iSCSI                        |
      |   WinRM (TCP 5985)                  |        |  (PVCs Block RWX, lun + SCSI-3 PR)
      +---------------------------------> sqllab-dc1   sqllab-fci-n1 <--------> sqllab-fci-n2
                                            AD DS, DNS,    nó 1                    nó 2
                                            share witness  \__ cluster de failover do Windows __/
                                                              FCI SQL Server 2016 SP2 "SQLFCI"
                                                              (discos: quorum 1G, SQLData E: 4G, SQLLog F: 2G)
```

Os dois nós do cluster rodam em hosts Harvester diferentes e enxergam as mesmas três LUNs como discos `lun` do KubeVirt com `reservation: true`. Assim o Windows Failover Clustering usa reservas persistentes SCSI-3 para isolar (fencing) o nó que perdeu o cluster.

## Requisitos

**Harvester**
- v1.9.0 (única versão suportada pelo `harvester-pr`), com pelo menos dois nós agendáveis e Longhorn padrão. Os testes usaram um cluster de 3 nós com um nó witness.
- Uma rede de VM na sua LAN (um NetworkAttachmentDefinition, `LAN_NAD` no `env.example`) com 5 IPs estáticos livres na mesma sub-rede e um gateway. As VMs do laboratório não precisam de internet (buscam as ISOs em um servidor de ISOs dentro do cluster), mas a construção da imagem dourada precisa: a VM de build baixa o Cloudbase-Init de `cloudbase.it` e o cluster puxa a imagem do driver VMDP de `registry.suse.com`.
- Capacidade aproximada: 30 GiB de memória de VM e 10 vCPUs (DC 6 GiB / 2, cada nó 12 GiB / 4), 3 discos raiz de 60 GiB, 36 GiB para a imagem dourada (mais cerca de 56 GiB temporários durante a construção), 8 GiB para o volume do servidor de ISOs, cerca de 4,2 GiB de imagens ISO e as 3 LUNs compartilhadas (7 GiB, mantidas pelo Longhorn com 2 réplicas).

**Sua estação**
- `kubectl` com o kubeconfig do Harvester, `helm`, `virtctl`, `python3` (com `venv`), `git`, `curl` e acesso `ssh` ao nó que hospeda o alvo LIO.
- Acesso de rede aos IPs das VMs na porta TCP 5985 (WinRM): o runbook configura todo o convidado a partir daqui.

**Mídia** (não incluída): ISO de avaliação do Windows Server 2022, ISO do SQL Server 2016 SP2 e ISO do virtio-win. Veja [iso/README.md](iso/README.md).

**Tempo**: cerca de 25 minutos para a imagem dourada (uma vez) e depois cerca de 1,5 hora para o runbook (clones das VMs 20 min, DC 9, preparo e ingresso dos nós 8, cluster e validação 7, SQL 30, testes de failover 10).

## Estrutura

| Caminho | O quê |
|---|---|
| `runbook/` | scripts numerados 00-99 (comece por `runbook/README.md`) e PowerShell do convidado em `ps/` |
| `docs/golden-image.md` | como construir a imagem dourada do Windows com o projeto de terceiros [harvester-windows-cloudbase](https://github.com/abonillabeeche/harvester-windows-cloudbase) (`golden/fetch-reference.sh` o clona) |
| `docs/shared-pr-disks.md` | procedimento genérico de discos compartilhados com PR no Harvester (UI + YAML), requisitos e limites |
| `docs/demo.md`, `docs/demo.pt-BR.md` | roteiro de demonstração de 15 minutos (EN / PT-BR) |
| `lio/` | chart Helm do alvo iSCSI LIO, values, PVs/PVCs, CRs CloudInit |
| `vm/` | gerador de VMs (`gen-vm.sh`) e executores WinRM |
| `harvester-pr` | liga/desliga o gate PersistentReservation do KubeVirt (somente Harvester v1.9.0) |
| `iso/` | onde colocar a mídia de instalação (veja `iso/README.md`) |
| `scripts/verify-clean.sh` | verificação pré-publicação de dados pessoais e segredos (para quem fizer fork) |

## Início rápido

1. Confira os requisitos acima. Baixe as ISOs em `iso/` ([iso/README.md](iso/README.md)).
2. `cp env.example env.local` e ajuste o caminho do kubeconfig, os nomes dos nós (`kubectl get nodes`: `NODE_A` roda o DC, o nó 1 e o alvo LIO; `NODE_B` roda o nó 2 e o servidor de ISOs), os IPs e a rede. As senhas já vêm com um valor de laboratório; troque se quiser.
3. Ative o feature gate de PR: `./harvester-pr enable --apply` (veja `docs/shared-pr-disks.md`). Atenção: um upgrade do Harvester desfaz isso.
4. Construa a imagem dourada: [docs/golden-image.md](docs/golden-image.md).
5. Execute os passos de `runbook/` em ordem, ou `runbook/run-all.sh` para os passos 00-10 e a verificação. **O passo 01 exige uma ação manual:** o script cria um CR CloudInit e imprime um comando. Execute-o como root, via SSH, no nó que hospeda o alvo LIO (`NODE_A`) e depois continue:
   ```
   sudo elemental cloud-init -s boot /oem/96_lio_aptpl.yaml
   ls -ld /etc/target/pr        # precisa existir
   ```
   O `run-all.sh` pausa nesse ponto até você apertar Enter. Isso só é necessário para o LIO Linux que faz o papel da SAN; uma SAN real não precisa.
6. Meça os failovers com `runbook/11-failover-tests.sh planned | stop --yes | kill --yes` e apresente com `docs/demo.pt-BR.md`.

Se um passo falhar, `runbook/README.md` lista os problemas encontrados na construção e suas correções (Windows Update, reservas SCSI-3 antigas, a falha do AddNode do SQL, entre outros).

## Limpeza

| O quê | Como |
|---|---|
| As 3 VMs Windows e seus discos raiz | `runbook/99-teardown.sh --yes` (mantém as LUNs, a imagem dourada e a configuração dos nós) |
| Pod do servidor de ISOs, seu volume e as duas imagens ISO | `runbook/03-iso-server.sh down` |
| LUNs compartilhadas e o alvo LIO (não testado) | apague os PVCs e PVs `fci-quorum`, `fci-sqldata`, `fci-sqllog` e depois `helm uninstall lio-san` |
| Imagem dourada | `kubectl -n labs delete virtualmachineimage win2022-cloudbase` |

Antes de reconstruir nas mesmas LUNs defina `WIPE_LUNS=1` em `env.local`: reservas SCSI-3 antigas sobrevivem à exclusão das VMs e bloqueariam o novo cluster.

## Bom saber

- O Windows Update fica desligado nas VMs de propósito (passo 05): uma atualização cumulativa instalada enquanto o Failover-Clustering é adicionado faz a instalação falhar e ser desfeita.
- Multipath no caminho de dados e uma SAN real não foram testados aqui (o artigo em Leitura adicional cobre os dois). O `./harvester-pr enable` não foi executado novamente a partir do estado final deste repositório.

## Leitura adicional

- [Windows failover clusters on SUSE Virtualization: shared SAN LUNs with SCSI-3 reservations](https://blog.5glinux.com/posts/wsfc-sql-fci-shared-san-luns-suse-virtualization/) (Alejandro Bonilla, 5glinux; em inglês): um artigo mais detalhado sobre o mesmo assunto, feito em uma SAN real (LUNs iSCSI NetApp ONTAP via Trident, com multipath).

## Créditos e licença
MIT, veja [LICENSE](LICENSE). A abordagem da imagem dourada é baseada no [harvester-windows-cloudbase](https://github.com/abonillabeeche/harvester-windows-cloudbase) (Apache-2.0, clonado separadamente). Windows, SQL Server e a ISO do virtio-win estão sujeitos às suas próprias licenças e não são distribuídos aqui.
