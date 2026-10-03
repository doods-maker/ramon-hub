# Tela Hoje da Recepção (fila sem responsável + atendimentos do ADVBOX) e da
# advogada (conversas atribuídas + semana no ADVBOX). Caixa = inbox com portaria_enabled.
# ADVBOX fora/cota estourada → o bloco vem nil com advbox_fora: true e o resto segue.
class Ramon::Hoje::Escritorio
  pattr_initialize [:account!, :user!, :papel!]

  # Celular BR em qualquer grafia: com/sem 55 e com/sem o 9º dígito (DDD + 9 + 8).
  def self.variantes_telefone(telefone)
    digitos = telefone.to_s.gsub(/\D/, '')
    nacional = digitos.length > 11 && digitos.start_with?('55') ? digitos.delete_prefix('55') : digitos
    return [] if nacional.length < 10

    ddd = nacional[0, 2]
    local = nacional[2..]
    locais = [local, local.length == 9 && local.start_with?('9') ? local[1..] : "9#{local}"]
    locais.flat_map { |l| ["#{ddd}#{l}", "55#{ddd}#{l}"] }.uniq
  end

  def perform
    papel == 'advogada' ? advogada : recepcao
  end

  private

  def caixa
    account.conversations.open.joins(:inbox).where(inboxes: { portaria_enabled: true })
  end

  def sem_responsavel
    caixa.where(assignee_id: nil, team_id: nil)
  end

  def recepcao
    atendimentos, fora = advbox { atendimentos_de_hoje }
    { sem_responsavel: linhas(sem_responsavel), atendimentos: atendimentos, caixa: contagem, advbox_fora: fora }
  end

  def advogada
    semana, fora = advbox { Ramon::SemanaAdvboxService.new(account).para(user) }
    { atribuidas: linhas(caixa.where(assignee_id: user.id)), semana: semana, advbox_fora: fora }
  end

  def advbox
    [yield, false]
  rescue *Ramon::AdvboxCache::ERROS => e
    Rails.logger.warn("[ramon_hoje] ADVBOX fora: #{e.message}")
    [nil, true]
  end

  def linhas(scope)
    scope.preload(:contact).reorder('conversations.created_at').limit(20).map { |conversa| linha(conversa) }
  end

  def linha(conversa)
    contato = conversa.contact
    {
      conversa_id: conversa.display_id, nome: contato&.name.presence, telefone: contato&.phone_number, cliente: cliente?(contato),
      ultima_mensagem: conversa.messages.incoming.last&.content.to_s.truncate(80),
      esperando_desde: (conversa.waiting_since || conversa.created_at).iso8601
    }
  end

  # Cliente = telefone no Painel do Cliente (ADVBOX); o resto é "número novo".
  def cliente?(contato)
    variantes = Ramon::Hoje::Escritorio.variantes_telefone(contato&.phone_number)
    variantes.any? && PortalCliente.exists?(account: account, telefone: variantes)
  end

  def contagem
    controladoria = caixa.where(team_id: account.teams.where(name: 'controladoria').select(:id))
    {
      sem_responsavel: sem_responsavel.count,
      controladoria: controladoria.count,
      com_advogadas: caixa.where.not(assignee_id: nil).where.not(id: controladoria.select(:id)).count
    }
  end

  def atendimentos_de_hoje
    chegadas = Chegada.where(account: account).de_hoje.where.not(advbox_post_id: nil).index_by(&:advbox_post_id)
    Ramon::AgendaHojeService.new(account).perform.sort_by { |linha| linha[:hora].to_s }.map do |linha|
      chegada = chegadas[linha[:advbox_post_id]]
      linha.merge(situacao: situacao(chegada), chegou_em: chegada&.created_at&.iso8601)
    end
  end

  def situacao(chegada)
    return 'nao_chegou' unless chegada

    chegada.respondido_em ? 'atendido' : 'aguardando'
  end
end
