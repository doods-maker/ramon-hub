# Descobre as pastas que a esteira deixou prontas (arquivo _pasta-pronta.json na pasta do protocolo),
# lista por advogado e avisa só o responsável pelo sino (sem NtfyPushJob: o título é dado interno).
# Contrato do marcador: {"responsavel_email": "...", "titulo": "..."}; ambos opcionais.
# Marcador de pasta que já virou petição é renomeado e sai da busca: marcadores abertos ≈ itens abertos.
# Roda a cada 5 min. Logs: só classe e ids (LGPD).
class Ramon::PastasProntasJob < ApplicationJob
  queue_as :scheduled_jobs

  LIMITE_MARCADOR = 64.kilobytes
  LIMITE_TITULO = 200

  def perform
    return unless Ramon::DriveClient.configured?

    account = Account.find(ENV.fetch('RAMON_PETICOES_ACCOUNT_ID', 2))
    # Falha de listagem sobe antes de qualquer limpeza: Drive fora do ar não apaga a lista.
    marcadores = Ramon::DriveClient.marcadores_de_pasta_pronta
    com_peticao = account.peticoes.where(pela_pasta: true).pluck(:drive_pasta_id)
    existentes = account.pastas_prontas.pluck(:drive_pasta_id)
    vivas = marcadores.filter_map { |m| registrar(account, m, existentes, com_peticao) }
    # Lista vazia não prova que o Drive não tem marcadores: só a regra da petição (que não depende da listagem) roda.
    limpar(account, com_peticao, vivas.presence)
  end

  private

  # Devolve o id da pasta (o marcador existe, mesmo que ignorado ou quebrado); nil se o marcador não tem pasta.
  def registrar(account, marcador, existentes, com_peticao)
    pasta_id = Array(marcador[:parents]).first
    return if pasta_id.blank?

    if com_peticao.include?(pasta_id)
      aposentar(marcador[:id])
    elsif existentes.exclude?(pasta_id)
      criar(account, pasta_id, marcador)
    end
    pasta_id
  rescue StandardError => e
    Rails.logger.error("PastasProntasJob: #{e.class} marcador=#{marcador[:id]}")
    pasta_id
  end

  def aposentar(marcador_id)
    Ramon::DriveClient.aposentar_marcador(marcador_id)
  rescue StandardError => e
    Rails.logger.warn("PastasProntasJob: aposentar marcador falhou #{e.class} marcador=#{marcador_id}")
  end

  # Ignora (com log) marcador grande demais ou de pasta fora da raiz do escritório: a busca é por nome no Drive todo.
  def criar(account, pasta_id, marcador)
    return log_ignorado('grande demais', marcador) if marcador[:size].to_i > LIMITE_MARCADOR
    return log_ignorado('fora da raiz', marcador) unless Ramon::DriveClient.dentro_da_raiz?(pasta_id)

    dados = JSON.parse(Ramon::DriveClient.download(marcador[:id]).first)
    raise JSON::ParserError, 'não é objeto' unless dados.is_a?(Hash)

    gravar(account, pasta_id, dados)
  rescue JSON::ParserError
    Rails.logger.warn("PastasProntasJob: JSON inválido marcador=#{marcador[:id]}")
  rescue ActiveRecord::RecordNotUnique
    nil # outra rodada criou antes
  end

  def log_ignorado(motivo, marcador)
    Rails.logger.warn("PastasProntasJob: marcador ignorado (#{motivo}) marcador=#{marcador[:id]}")
  end

  # Linha e sinos na mesma transação: sem linha órfã de aviso (nem aviso de linha desfeita).
  def gravar(account, pasta_id, dados)
    titulo = dados['titulo'].to_s.strip.truncate(LIMITE_TITULO).presence
    PastaPronta.transaction do
      pasta = account.pastas_prontas.create!(drive_pasta_id: pasta_id, titulo: titulo,
                                             responsavel: responsavel_de(account, dados['responsavel_email']))
      avisar(account, pasta)
    end
  end

  # Só quem pode usar a lista (administrador ou time advogados); outro e-mail conta como sem dono.
  def responsavel_de(account, email)
    email = email.to_s.strip.downcase
    return if email.blank?

    user = account.users.from_email(email)
    return unless user && (Ramon::Papeis.gestor_ids(account).include?(user.id) ||
                           Ramon::Papeis.membro?(account, user, Ramon::Papeis::JURIDICO))

    user
  end

  # Só o responsável; sem dono, os administradores.
  def avisar(account, pasta)
    ids = pasta.responsavel ? [pasta.responsavel_id] : Ramon::Papeis.gestor_ids(account)
    rotulo = pasta.titulo || I18n.t('notifications.pasta_sem_titulo')
    User.where(id: ids).find_each do |user|
      user.notifications.create!(notification_type: 'ramon_pasta_pronta', account: account, primary_actor: pasta, meta: { 'label' => rotulo })
    end
  end

  # Petição existente tira o item sempre; marcador que sumiu só quando a listagem trouxe algum marcador.
  def limpar(account, com_peticao, vivas)
    itens = account.pastas_prontas
    sai = itens.where(drive_pasta_id: com_peticao)
    sai = sai.or(itens.where.not(drive_pasta_id: vivas)) if vivas
    sai.find_each(&:destroy)
  end
end
