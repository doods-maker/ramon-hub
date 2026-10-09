# Fecha o extrato da variável do mês anterior no 3º dia útil (regulamento §6).
# A tela também fecha na 1ª leitura depois da data; o job garante o fechamento
# mesmo se ninguém abrir o Extrato.
class Ramon::ExtratoFechamentoJob < ApplicationJob
  queue_as :scheduled_jobs

  # Regra fixa (decisão do Eduardo 08/10): todas as contas, todo dia às 00:20 (config/schedule.yml).
  def perform
    mes = Ramon::ExtratoFechamento.hoje.prev_month.beginning_of_month
    return unless Ramon::ExtratoFechamento.fechado?(mes)

    Account.find_each { |account| Ramon::ExtratoFechamento.fechar!(account, mes) }
  end
end
