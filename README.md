# platform-infra

Infraestrutura como código (Terraform) da plataforma de dados event-driven. O repositório contém:
- a **landing zone** Azure;
- os objetos compartilhados do **Unity Catalog**;
- o **onboarding de domínios** (event hubs, identidades, catálogos);
- a **configuração GitOps** do AKS (Flux).

## Estrutura

```
bootstrap/          # 1x, local: storage do tfstate + identidades OIDC do GitHub (infra, deployer)
modules/domain/     # módulo de onboarding de domínio (ADR-0004)
stacks/
  core/             # RG, ADLS Gen2, Event Hubs, ACR, AKS (+ extensão Flux), Databricks, Access Connector
  lakehouse/        # UC: storage credential, external location "lakehouse", SP deployer no workspace
  domains/          # module.domain por domínio + azurerm_kubernetes_flux_configuration
scripts/
  configure-github.sh   # grava Variables/Environments nos repositórios (OIDC)
```

Ordem de aplicação: `core` → `lakehouse` → `domains`. Cada stack lê os anteriores via `terraform_remote_state`.

## O que cada domínio recebe (`modules/domain`)

| Recurso | Nome (ex.: `pedidos`, dev) |
|---|---|
| Event hub por agregado (+ Capture Avro → ADLS) | `pedidos.pedido.v1` |
| Consumer groups declarados | `pagamentos` |
| Schema group (JSON) | `pedidos` |
| Container de capture | `capture-pedidos` |
| Managed Identity + federated credential por workload | `id-pedidos-pedidos-api-dev` ↔ `system:serviceaccount:pedidos:pedidos-api` |
| RBAC | Data Sender nos próprios hubs, Data Receiver no namespace |
| External location (read-only) do capture | `pedidos_dev_capture` |
| Catálogo + schemas | `pedidos_dev.{bronze,silver,gold}` |

**Onboarding de um domínio:** um PR adicionando uma entrada em `stacks/domains/envs/<env>.tfvars`. O plan aparece comentado no PR, e o merge aplica.

## GitOps

O stack `domains` cria a `azurerm_kubernetes_flux_configuration`, que aponta para o [`platform-gitops`](https://github.com/ViniciusOtoni/platform-gitops) e tem duas Kustomizations: `infrastructure` e `domains`. Os valores que só o Terraform conhece são injetados nos manifests via `postBuild.substitute`:
- `AZURE_TENANT_ID`
- `EVENTHUB_NAMESPACE_FQDN`
- `ACR_LOGIN_SERVER`
- `ENVIRONMENT`
- `<DOMINIO>_<WORKLOAD>_CLIENT_ID`

## CI/CD

Pipeline em `.github/workflows/terraform.yml`, que usa o [`platform-cicd-workflows`](https://github.com/ViniciusOtoni/platform-cicd-workflows):

| Evento | O que roda |
|---|---|
| PR | `ci-terraform`: fmt + validate em tudo; **plan** de cada stack comentado no PR |
| Merge na `main` | `cd-terraform`: apply `core` → `lakehouse` → `domains` (Environment `dev`) |

Enquanto a variável `AZURE_CLIENT_ID` não estiver definida no repositório, roda só a validação (sem plan nem apply).

## Primeira execução (passo a passo)

> ⚠️ Os passos 1 e 4 **criam recursos com custo** na Azure.

Pré-requisitos: Azure CLI (`az login` com um usuário Owner da subscription), Terraform ≥ 1.9 e `gh` autenticado.

1. **Bootstrap** (local):
   ```bash
   cd bootstrap
   terraform init
   terraform apply -var subscription_id=<SUBSCRIPTION_ID>
   ```
2. **Preencher os IDs** (não são segredos), usando os outputs do bootstrap, em:
   - `stacks/core/envs/dev.tfvars`: `subscription_id`, `deployer_principal_id` (= `deployer_object_id`)
   - `stacks/lakehouse/envs/dev.tfvars`: `deployer_client_id`
   - `stacks/domains/envs/dev.tfvars`: `subscription_id`
3. **Configurar o GitHub:**
   ```bash
   scripts/configure-github.sh platform-infra infra dev
   ```
4. Abrir um PR com o passo 2. Revisar os plans. Fazer o merge, que aplica os stacks.
5. **Configurar os repositórios de domínio** quando forem criados:
   ```bash
   scripts/configure-github.sh pedidos-service deployer dev prd -- ACR_NAME=<acr>
   ```

### Custo e limpeza

Em dev, os itens que custam são:
- AKS: 1 nó D2as_v5.
- Event Hubs Standard: 1 TU, mais o Capture.
- Databricks: só cobra quando há compute rodando.
- ADLS e ACR Basic: centavos.

Para destruir o ambiente, rode `terraform destroy` na ordem inversa: `domains` → `lakehouse` → `core`.

## Decisões e pontos a validar

- **azurerm fixado em `~> 4.x`.** A 5.x já existe; a migração será tratada em um ADR próprio.
- **Event Hubs com `local_authentication_enabled = false`** (sem SAS). Os clientes usam Workload Identity, e o Kafka usa OAuth.
- **ADLS com shared key habilitada**, porque o Capture via azurerm não suporta managed identity no destino. Isso deve ser reavaliado.
- **Schema Registry:** o RBAC das workloads no schema group será adicionado na Fase 2, junto com o `platform-event-sdk`.
- **File events do UC:** o Access Connector já tem as roles de fila e Event Grid. A habilitação na external location será validada na Fase 4.
- **Primeiro PR antes do `core` aplicado:** o plan de `lakehouse`/`domains` falha porque o state do `core` ainda não existe. O fluxo esperado é aplicar o `core` primeiro.

## ADRs relacionados

ADR-0001, 0003, 0004, 0006, 0007 e 0008, em `platform-docs/adr` (local).
