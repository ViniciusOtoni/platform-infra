# Onboarding de domínio = PR adicionando uma entrada em "domains" (ADR-0004).
# Preencha subscription_id após o bootstrap.
subscription_id = "00000000-0000-0000-0000-000000000000"
environment     = "dev"

domains = {
  pedidos = {
    aggregates = [
      {
        name            = "pedido"
        partition_count = 2
        # Pagamentos reage a PedidoCriado/PedidoCancelado (saga por coreografia).
        consumer_groups = ["pagamentos"]
      },
    ]
    workloads = ["pedidos-api", "outbox-relay"]
  }
  # pagamentos: on-boarded na Fase 5, via template (prova do self-service).
}
