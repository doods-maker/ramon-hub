# Fecha o extrato da variável do mês anterior no 3º dia útil (regulamento §6).
# A tela também fecha na 1ª leitura depois da data; o job garante o fechamento
# mesmo se ninguém abrir o Extrato.
class Ramon::ExtratoFechamentoJob < ApplicationJob
  queue_as :scheduled_jobs

  # B5-conta: sem conta = o cron (as contas cujo fluxo "Fechamento do extrato" não assumiu); com conta = o fluxo ou a reserva.
  def perform(account_id = nil)
    mes = Ramon::ExtratoFechamento.hoje.prev_month.beginning_of_month
    return unless Ramon::ExtratoFechamento.fechado?(mes)

    Ramon::Fluxos::Rotinas::Conta.cada_conta('fechamento_extrato', account_id) do |account|
      Ramon::ExtratoFechamento.fechar!(account, mes)
    end
  end
end
