# Cobrança da etapa Documentos (spec Etapa Documentos §7; regra fixa, aba "Do sistema"): a cada 15 min, para cada lead em
# Documentos que entrou pela cobrança (Ramon::Documentos::Entrada grava entrou_em), com algo pendente no checklist e a conversa
# com a IA (Ramon::Documentos::PassoAPasso.sai_agora?), faz o passo que o relógio (Ramon::Documentos::Relogio) diz:
# - abertura e lembretes → Ramon::Documentos::Envio; sem permissão (janela fechada e sem modelo aprovado) → silêncio direto;
# - acompanhamento → sino ao responsável (Ramon::Documentos::Responsavel), a IA segue atendendo;
# - silêncio e travado → nota com o motivo + bot_handoff!: o handoff de Documentos (PR 3) passa a conversa para o responsável.
# Idempotente: decide e grava a marca do passo (update_columns, sem os callbacks de cadência: lição do B4.3) sob o lock do lead;
# o envio vem depois do lock. Duas rodadas juntas fazem o passo uma vez; se o envio falhar, não repete (antes faltar que spammar).
# Chave RAMON_ETAPA_DOCUMENTOS desligada: não faz nada.
class Ramon::Documentos::CobrancaJob < ApplicationJob
  queue_as :scheduled_jobs

  CHAVE = Ramon::Documentos::Relogio::CHAVE
  CONFIG = Ramon::Documentos::Relogio::CONFIG
  NOMES = { abertura: 'a apresentação', lembrete_1: 'o lembrete 1', lembrete_2: 'o lembrete 2' }.freeze
  ENVIOS = NOMES.keys.freeze
  CANAIS = { texto: 'texto livre, na janela de 24 h', modelo: 'modelo da Meta, fora da janela de 24 h' }.freeze
  MOTIVOS = {
    silencio: 'Cobrança: silêncio — o cliente não respondeu à apresentação nem aos 2 lembretes (ou a janela do WhatsApp ' \
              'fechou e a caixa não tem o modelo aprovado).',
    travado: 'Cobrança: travado — 2 dias úteis sem documento novo, mesmo conversando com a IA.'
  }.freeze

  def perform
    return unless Ramon::EtapaDeGanho.documentos_ligado?

    candidatos.find_each do |lead|
      passo = reservar(lead)
      executar(lead, passo) if passo
    rescue StandardError => e
      Rails.logger.warn("[Ramon::Documentos::CobrancaJob] lead #{lead.id}: #{e.class}: #{e.message}")
    end
  end

  private

  def candidatos
    Lead.joins(:lead_stage).where(lead_stages: { label: Ramon::EtapaDeGanho::DOCUMENTOS, is_won: true })
        .where("leads.custom_attributes -> '#{CHAVE}' ->> 'entrou_em' IS NOT NULL")
  end

  # Sob o lock (relê o lead): ainda em Documentos, algo pendente, conversa com a IA → o passo vencido, já marcado.
  def reservar(lead)
    lead.with_lock do
      conversa = lead.conversation
      next unless Ramon::EtapaDeGanho.conduzida?(lead.lead_stage) && lead.docs_pendentes.any? && conversa &&
                  Ramon::Documentos::PassoAPasso.sai_agora?(conversa)

      passo = Ramon::Documentos::Relogio.proximo_passo(estado: estado(lead, conversa), agora: Time.current)&.dig(:passo)
      marcar(lead, passo) if passo
      passo
    end
  end

  # A última mensagem do cliente vem da conversa (upload do portal incluído: é o cliente agindo).
  def estado(lead, conversa)
    lead.custom_attributes[CHAVE].merge('ultima_resposta_em' => conversa.messages.incoming.maximum(:created_at)&.iso8601)
  end

  def marcar(lead, passo)
    cobranca = lead.custom_attributes[CHAVE].merge("#{passo}_em" => Time.current.iso8601)
    lead.update_columns(custom_attributes: lead.custom_attributes.merge(CHAVE => cobranca)) # rubocop:disable Rails/SkipsModelValidations
  end

  def executar(lead, passo)
    if ENVIOS.include?(passo)
      enviar(lead, passo)
    elsif passo == :acompanhamento
      acompanhar(lead)
    else
      passar(lead, passo)
    end
  end

  # Cada envio: linha no histórico do lead e linha de custo em Uso e custo (texto livre também é cobrado desde 01/10/2026).
  def enviar(lead, passo)
    canal = Ramon::Documentos::Envio.mandar(lead, passo)
    return sem_permissao(lead, passo) if canal == :sem_permissao

    registrar(lead, "enviou #{NOMES.fetch(passo)} (#{CANAIS.fetch(canal)})")
    Ramon::LlmUso.registrar_whatsapp(lead, model: canal == :modelo ? "modelo #{CONFIG.dig('modelo', 'nome')}" : 'texto livre',
                                           custo_usd: CONFIG['custo_usd_por_mensagem'])
  end

  def sem_permissao(lead, passo)
    registrar(lead, "#{NOMES.fetch(passo)} não saiu: janela de 24 h fechada e a caixa sem o modelo aprovado")
    lead.with_lock { marcar(lead, :silencio) }
    passar(lead, :silencio)
  end

  def acompanhar(lead)
    falta = lead.docs_pendentes.pluck(:title).join(', ')
    Ramon::AvisoDaIa.avisar(lead, "#{lead.name} está em Documentos sem avanço hoje: faltam #{falta}",
                            "Documentos: sem avanço (#{Ramon::NtfyPushJob.rotulo(lead)})", 'A IA segue atendendo; confira se está andando',
                            user_ids: [Ramon::Documentos::Responsavel.de(lead)&.id].compact)
    registrar(lead, 'acompanhamento: equipe avisada no sino, a IA segue atendendo')
  end

  # O motivo vai na nota que o handoff de Documentos lê (Ramon::Documentos::Handoff::MARCA); ele atribui, anota o que falta e avisa.
  def passar(lead, passo)
    conversa = lead.conversation
    conversa.messages.create!(message_type: :outgoing, private: true, account_id: conversa.account_id, inbox_id: conversa.inbox_id,
                              content: MOTIVOS.fetch(passo), content_attributes: { Ramon::Documentos::Handoff::MARCA => true })
    conversa.bot_handoff!
    registrar(lead, "#{passo == :silencio ? 'silêncio' : 'travado'}: a conversa foi para a equipe")
  end

  # O mesmo tipo da entrada em Documentos (Ramon::Documentos::Entrada): o histórico do lead já sabe mostrar.
  def registrar(lead, texto) = lead.lead_activities.create!(account: lead.account, kind: 'documentos', to_value: "Cobrança: #{texto}")
end
