# Observador do funil: lê a conversa do lead, pede ao LLM UMA decisão em JSON (etapa, perda, reunião, promessas,
# pendências, temperatura) e entrega a Ramon::FunilObservador::Aplicar, que decide o que cada chave de peça permite.
# Nada é enviado ao cliente. TransientError sobe para o job tentar de novo; o resto vira nil + log.
class Ramon::FunilObservador
  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o observador interno do funil comercial de um escritório de advocacia previdenciária e trabalhista no Brasil.
    Você NÃO fala com o cliente. Receberá a ficha e a conversa de UM lead. Devolva APENAS um JSON válido
    (sem markdown, sem comentários) com exatamente este formato:
    {"etapa": "qualificacao" | "ultima_chance" | null, "etapa_motivo": "1 frase",
     "perdido": {"motivo": "<nome exato da lista>", "frase": "1 frase"} | null,
     "reuniao": {"inicio": "AAAA-MM-DDTHH:MM", "frase": "1 frase"} | null,
     "promessas": [{"o_que": "texto curto", "prazo": "AAAA-MM-DD", "documento": true}],
     "promessas_cumpridas": [<id da tarefa>],
     "pendencias": ["<nome curto do documento>"],
     "temperatura": "quente" | "morno" | "frio", "temperatura_motivo": "1 frase"}

    Regras obrigatórias:
    - Decida só pelo que está escrito na conversa.
    - Se a ficha lista uma ação que a equipe desfez, decida só por fatos do cliente posteriores a esse desfazer.
    - "qualificacao" só quando o cliente respondeu a triagem e o caso cabe na tese.
    - "ultima_chance" só depois da reunião, com objeção ("vou pensar", preço, família).
    - "perdido" só com recusa clara do cliente; o motivo é o nome exato de um item da lista fornecida.
    - "reuniao" só com dia e hora exatos aceitos pelos dois, no fuso de São Paulo.
    - Promessa com data vaga: use o 1º dia útil citado.
    - Não repita promessa que já está nas tarefas "Cobrar:" listadas.
    - "pendencias" = só documentos que o cliente disse que vai mandar e ainda não mandou; não copie a checklist nem o exemplo.
    - "promessas_cumpridas" só com ids das tarefas "Cobrar:" listadas, quando a conversa mostra que foram cumpridas.
    - Nunca prometa resultado do caso nem prazo do INSS.
  PROMPT

  def initialize(lead)
    @lead = lead
  end

  def perform
    texto = Ramon::Transcricao.de(@lead.conversation, com_hora: true)
    return nil if texto.blank?

    decisao = decidir(texto)
    Aplicar.new(@lead, decisao).perform if decisao
    colher
    decisao
  end

  private

  # A colheita não depende da decisão do LLM (nem de ela existir), mas não roda em lead que o Aplicar acabou de ganhar/perder.
  # Como temperatura: sem FunilAcao (ruído no chip e no resumo) e só com a peça on — em ensaio não faz nada.
  # Em job próprio (com retry): um TransientError aqui faria o observador repetir e pagar a decisão de novo.
  # Tese sem colheita: o serviço não faz nada (extractable?).
  def colher
    return unless Ramon::FunilAutomatico.modo(account, 'colheita') == 'on'
    return if @lead.reload.won_at.present? || @lead.lost_at.present?

    Ramon::ColheitaExtractionJob.perform_later(lead_id: @lead.id)
  end

  def account = @lead.account

  def decidir(transcricao)
    result = Ramon::LlmClient.complete(**Ramon::LlmEscolha.para(account, 'copiloto'),
                                       system: SYSTEM_PROMPT, user: user_prompt(transcricao),
                                       funcao: 'funil_observador', account_id: account.id, lead_id: @lead.id)
    parse(result.content)
  rescue Ramon::LlmClient::TransientError
    raise
  rescue StandardError => e
    Rails.logger.warn("FunilObservador: LLM falhou p/ lead #{@lead.id} (#{e.class}) — pulando")
    nil
  end

  def parse(content)
    parsed = JSON.parse(content.to_s.sub(/\A```(?:json)?\s*/, '').sub(/```\s*\z/, ''))
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    Rails.logger.warn("FunilObservador: JSON inválido p/ lead #{@lead.id} — descartando")
    nil
  end

  # Pseudonimizado (LGPD): o texto inteiro só sai daqui mascarado.
  def user_prompt(transcricao)
    Ramon::Pseudonymizer.mask([ficha, transcricao].join("\n\n"), names: [@lead.name, @lead.contact&.name])
  end

  def ficha
    ["Hoje: #{agora} (horário de São Paulo).",
     "Etapa atual: #{@lead.lead_stage&.name || 'não informada'}.",
     "Tese: #{@lead.thesis&.name || 'não informada'}.",
     "Documentos pendentes: #{lista(docs_pendentes, ', ', 'nenhum')}.",
     "Motivos de perda (use o nome exato): #{account.lost_reasons.pluck(:name).join('; ')}.",
     "Tarefas \"Cobrar:\" abertas (id — título): #{lista(cobrancas, '; ', 'nenhuma')}.", *desfeitas].join("\n")
  end

  def agora
    hoje = Time.current.in_time_zone(Ramon::ReuniaoAgendamento::TIME_ZONE)
    "#{Ramon::ReuniaoAgendamento::DIAS_SEMANA[hoje.wday]} #{hoje.strftime('%d/%m/%Y %H:%M')}"
  end

  # O que a equipe desfez (30 dias): sem isso o LLM, relendo a mesma conversa, decide igual de novo.
  def desfeitas
    @lead.funil_acoes.where(desfeita_em: 30.days.ago..).order(:desfeita_em).map do |a|
      quando = a.desfeita_em.in_time_zone(Ramon::ReuniaoAgendamento::TIME_ZONE).strftime('%d/%m %H:%M')
      "A equipe desfez '#{[a.acao, a.alvo].compact_blank.join(': ')}' em #{quando}; só repita se houver fato novo do cliente depois disso."
    end
  end

  def lista(itens, separador, vazio) = itens.empty? ? vazio : itens.join(separador)

  def docs_pendentes
    @lead.doc_checklist.reject { |d| d[:status] == 'recebido' }.pluck(:title)
  end

  def cobrancas
    @lead.lead_tasks.open_tasks.where('title LIKE ?', 'Cobrar:%').pluck(:id, :title).map { |id, titulo| "#{id} — #{titulo}" }
  end
end
