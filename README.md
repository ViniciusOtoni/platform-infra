# platform-infra

Infraestrutura como código (Terraform) da plataforma de dados event-driven. O repositório contém:
- a **landing zone** Azure;
- o **Unity Catalog**;
- o **onboarding de domínios**;
- o **runtime efêmero** (Event Hubs, AKS + Flux, Postgres).

## Arquitetura do repositório

```
bootstrap/                 # 1x, local: storage do tfstate + Managed Identities OIDC (ADR-0009)
config/domains/<env>.yaml  # FONTE ÚNICA dos domínios on-boarded
modules/
  domain-data/             # parte persistente do domínio: container de capture, external location, catálogo UC
  domain-runtime/          # parte efêmera: event hubs + Capture, identidades, RBAC, database no Postgres
stacks/
  foundation/              # PERSISTENTE: RG, ADLS Gen2, ACR, Databricks + Access Connector
  lakehouse/               # PERSISTENTE: storage credential, external locations, SP deployer, module.domain_data
  runtime/                 # EFÊMERO: Event Hubs, AKS + Flux, Postgres Flexible, module.domain_runtime, flux configuration
scripts/configure-github.sh
```

Ordem: `foundation` → `lakehouse` → `runtime`. Cada stack lê os anteriores via `terraform_remote_state`.

## Persistente × efêmero (ADR-0010)

| Camada | O que tem | Quando aplica | Custo ocioso |
|---|---|---|---|
| `foundation` + `lakehouse` | Dados (ADLS, UC), imagens (ACR), workspace Databricks | Merge na `main` | ~US$ 5/mês |
| `runtime` | Event Hubs + Capture, AKS + Flux, Postgres, identidades das workloads | **Actions → `env` → up/down**; destroy automático às 00:00 BRT | US$ 0 |

Os eventos capturados e as tabelas do Lakehouse **sobrevivem** ao `down`. O banco transacional e o cluster são recriados do zero a cada `up`, com o cluster restaurado 100% pelo Git (GitOps).

## Onboarding de domínio

Um PR em `config/domains/dev.yaml`:

```yaml
pedidos:
  aggregates:
    - name: pedido
      consumer_groups: [pagamentos]
  workloads: [pedidos-api, outbox-relay]
  database: true
```

| Gera | Exemplo |
|---|---|
| Event hub por agregado com Capture → ADLS | `pedidos.pedido.v1` → `capture-pedidos/` |
| Consumer groups, schema group (JSON) | `pagamentos`, `pedidos` |
| Managed Identity + federated credential por workload | `id-pedidos-pedidos-api-dev` ↔ `system:serviceaccount:pedidos:pedidos-api` |
| Database no Postgres compartilhado (Entra-only) | `pedidos` |
| Catálogo UC + schemas | `pedidos_dev.{bronze,silver,gold}` |

O domínio também precisa de:
- subjects OIDC em `bootstrap/variables.tf`;
- `domains/<dominio>/` no [`platform-gitops`](https://github.com/ViniciusOtoni/platform-gitops).

## GitOps

O stack `runtime` cria a `azurerm_kubernetes_flux_configuration`, com as Kustomizations `infrastructure` e `domains`. Os valores que mudam a cada `up` são injetados nos manifests via `postBuild.substitute`:
- `AZURE_TENANT_ID`
- `EVENTHUB_NAMESPACE_FQDN`
- `ACR_LOGIN_SERVER`
- `POSTGRES_HOST`
- `ENVIRONMENT`
- `<DOMINIO>_<WORKLOAD>_CLIENT_ID`
- `<DOMINIO>_<WORKLOAD>_IDENTITY_NAME`

## CI/CD

| Workflow | Evento | O que roda |
|---|---|---|
| `terraform.yml` | PR | `ci-terraform`: fmt + validate em tudo; **plan** de cada stack comentado no PR |
| `terraform.yml` | Merge na `main` | `cd-terraform`: apply `foundation` → `lakehouse` |
| `env.yml` | Manual (`up`/`down`) e diário às 03:00 UTC (`down`) | `cd-terraform` no stack `runtime` (`destroy: true` no down) |

Os workflows vêm do [`platform-cicd-workflows@v1`](https://github.com/ViniciusOtoni/platform-cicd-workflows). Sem a variável `AZURE_CLIENT_ID`, roda só a validação.

## Restrições da assinatura (Azure for Students)

- **Regiões permitidas por policy:** `eastus2` (padrão), `canadacentral`, `southcentralus`, `mexicocentral` e `chilecentral`.
- **Cota:** 6 vCPUs no total, **0 em DASv5/DSv5**. O AKS também **rejeita a família B**, e só a DSv3 tem cota: por isso usa `Standard_D2s_v3`. O Databricks precisa de **serverless**.
- **Postgres Flexible bloqueado** em `eastus2` e `southcentralus` para a oferta Students: o servidor fica em `canadacentral` (variável `postgres_location`).
- **Tenant:** App Registrations bloqueadas (o usuário não vira owner). Por isso o OIDC usa Managed Identity (ADR-0009).

## Primeira execução

1. **Bootstrap** (local, uma vez). ✅ Já executado:
   ```bash
   cd bootstrap && terraform init
   terraform apply -parallelism=1 -var subscription_id=<SUBSCRIPTION_ID>
   ```
2. **GitHub:** `scripts/configure-github.sh platform-infra infra dev`.
3. **Merge na `main`:** aplica `foundation` + `lakehouse`.
4. **Sessão de estudo:** Actions → `env` → `up` (~15 min). Ao final, `down`.

## Pontos a validar no primeiro `up`

- Capture com Event Hubs sem SAS (`local_authentication_enabled = false`).
- `post_build.substitute` da flux configuration.
- Permissões de *file events* do UC (as roles de fila e Event Grid já estão no Access Connector).
- Disponibilidade de **serverless** no workspace da Azure for Students.

## ADRs relacionados

ADR-0001, 0003, 0004, 0006, 0007, 0008, 0009, 0010 e 0011, em `platform-docs/adr` (local).
