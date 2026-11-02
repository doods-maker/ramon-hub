# Descobre as pastas que a esteira deixou prontas (arquivo _pasta-pronta.json na pasta do protocolo),
# lista por advogado e avisa só o responsável pelo sino (sem NtfyPushJob: o título é dado interno).
# Contrato do marcador: {"responsavel_email": "...", "titulo": "..."}; ambos opcionais.
# Roda a cada 5 min. Logs: só classe e ids (LGPD).
class Ramon::PastasProntasJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless Ramon::DriveClient.configured?

    account = Account.find(ENV.fetch('RAMON_PETICOES_ACCOUNT_ID', 2))
    # Falha de listagem sobe antes da limpeza: Drive fora do ar não apaga a lista.
    pastas = Ramon::DriveClient.marcadores_de_pasta_pronta.filter_map { |m| registrar(account, m) }
    limpar(account, pastas)
  end

  private

  # Devolve o id da pasta (o marcador existe, mesmo que o JSON esteja quebrado); nil se o marcador não tem pasta.
  def registrar(account, marcador)
    pasta_id = Array(marcador[:parents]).first
    return if pasta_id.blank?

    criar(account, pasta_id, marcador[:id]) unless PastaPronta.exists?(account_id: account.id, drive_pasta_id: pasta_id) ||
                                                   account.peticoes.exists?(pela_pasta: true, drive_pasta_id: pasta_id)
    pasta_id
  rescue StandardError => e
    Rails.logger.error("PastasProntasJob: #{e.class} marcador=#{marcador[:id]}")
    pasta_id
  end

  def criar(account, pasta_id, marcador_id)
    dados = JSON.parse(Ramon::DriveClient.download(marcador_id).first)
    raise JSON::ParserError, 'não é objeto' unless dados.is_a?(Hash)

    responsavel = responsavel_de(account, dados['responsavel_email'])
    pasta = account.pastas_prontas.create!(drive_pasta_id: pasta_id, titulo: dados['titulo'].to_s.strip.presence, responsavel: responsavel)
    avisar(account, pasta)
  rescue JSON::ParserError
    Rails.logger.warn("PastasProntasJob: JSON inválido marcador=#{marcador_id}")
  rescue ActiveRecord::RecordNotUnique
    nil # outra rodada criou antes
  end

  def responsavel_de(account, email)
    email = email.to_s.strip.downcase
    account.users.from_email(email) if email.present?
  end

  # Só o responsável; sem dono, os administradores.
  def avisar(account, pasta)
    ids = pasta.responsavel ? [pasta.responsavel_id] : Ramon::Papeis.gestor_ids(account)
    rotulo = pasta.titulo || I18n.t('notifications.pasta_sem_titulo')
    User.where(id: ids).find_each do |user|
      user.notifications.create!(notification_type: 'ramon_pasta_pronta', account: account, primary_actor: pasta, meta: { 'label' => rotulo })
    end
  end

  # Marcador que sumiu ou petição que já existe: o item sai (com o sino dele).
  def limpar(account, vivas)
    com_peticao = account.peticoes.where(pela_pasta: true).select(:drive_pasta_id)
    account.pastas_prontas.where.not(drive_pasta_id: vivas).or(account.pastas_prontas.where(drive_pasta_id: com_peticao)).find_each(&:destroy)
  end
end
