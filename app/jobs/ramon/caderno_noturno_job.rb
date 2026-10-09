# Caderno de provas automático (Inteligência A5 — I-X6): 05:30 de Brasília, nas contas com a chave ligada
# (Inteligência → Testar → Casos de teste). A regra (o que mudou, teto, rodada em andamento) mora no
# Captain::CadernoNoturno (enterprise); no CI FOSS o job não faz nada.
# A chave da conta (account.settings) mora só aqui: o cron lê, o serviço pergunta (ligado?) e a tela grava (ligar!).
class Ramon::CadernoNoturnoJob < ApplicationJob
  CHAVE = 'ramon_caderno_noturno'.freeze

  queue_as :scheduled_jobs

  def self.ligado?(account) = ActiveModel::Type::Boolean.new.cast(account.settings&.dig(CHAVE)) == true

  def self.ligar!(account, ligado) = account.update!(settings: (account.settings || {}).merge(CHAVE => ligado))

  def perform
    return unless ChatwootApp.enterprise?

    Account.where("settings ->> ? = 'true'", CHAVE).find_each do |account|
      Captain::CadernoNoturno.new(account).perform
    rescue StandardError => e
      # uma conta com dado venenoso não pode abortar as demais nem virar retry-loop
      Rails.logger.error("CadernoNoturnoJob: conta #{account.id} falhou (#{e.class}: #{e.message})")
    end
  end
end
