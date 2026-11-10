# SQL Server 2016 Failover Cluster Instance no Harvester com discos `lun` compartilhados nativos (SCSI-3 PR)

Tutorial de laboratório: monta um cluster de duas VMs Windows Server 2022 / SQL Server 2016 SP2 (**FCI**) no **Harvester v1.9.0**, usando discos `lun` do KubeVirt com reservas SCSI-3 como armazenamento compartilhado, e executa testes de failover.

> **Somente laboratório.** Mídia de avaliação, senhas descartáveis (`Sqllab2026`, em `env.example`), sem hardening. Não use em produção.

- Visão geral, estrutura e passos: veja o [README.md](README.md) (inglês), com o mesmo conteúdo.
- Roteiro de demonstração em português: [docs/demo.pt-BR.md](docs/demo.pt-BR.md).
- Procedimento genérico de discos compartilhados com PR: [docs/shared-pr-disks.md](docs/shared-pr-disks.md) (inglês).
- Licença MIT, veja [LICENSE](LICENSE).
