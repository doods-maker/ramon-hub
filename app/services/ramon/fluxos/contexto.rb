# O que um passo enxerga: o alvo (lead/conversa) recarregado a cada passo + variáveis
# da execução. `dados` alimenta condições e o `{chave}` dos textos.
class Ramon::Fluxos::Contexto
  # o que o gatilho traz e vira variável: {texto} da mensagem, {quando} da reunião,
  # {regra} do evento do ADVBOX, {documento} do anexo casado com o checklist;
  # B4.1: os textos prontos da reunião ({evento}, {titulo}, {titulo_tarefa}, {resumo}, {resumo_antes}, {primeiro_nome})
  DO_GATILHO = %w[texto quando regra documento evento titulo titulo_tarefa resumo resumo_antes primeiro_nome].freeze

  # chaves que o próprio hub monta em `dados`: preencher_campo recusa (o campo nunca apareceria)
  RESERVADAS = (DO_GATILHO + %w[nome nome_completo telefone responsavel responsavel_id etapa etapa_id tese tese_id origem canal
                                valor prioridade caixa caixa_id status etiquetas documentos_completos documentos_faltantes
                                resposta_ia reuniao_de_pe horario_passou]).freeze

  attr_reader :execucao

  def initialize(execucao)
    @execucao = execucao
  end

  def lead = @lead ||= execucao.lead

  def conversa = @conversa ||= execucao.conversa

  def ensaio? = execucao.ensaio

  # campos livres primeiro: um campo chamado "nome" nunca pisa no nome do lead
  def dados
    @dados ||= campos_livres.merge(dados_lead, dados_funil, dados_conversa, dados_docs, dados_reuniao, dados_gatilho,
                                   execucao.contexto['vars'] || {})
  end

  def interpolar(texto)
    texto.to_s.gsub(/\{(\w+)\}/) { dados.key?(Regexp.last_match(1)) ? dados[Regexp.last_match(1)].to_s : Regexp.last_match(0) }
  end

  # Valor cru que o gatilho trouxe (ids e horários que não viram texto: inicio, quem_marcou_id, tarefa_ids, lead_id).
  def gatilho(chave) = execucao.contexto.dig('gatilho', chave)

  # Horário da reunião (B4.1): o 'inicio' que o gatilho mandou; sem ele ("Testar com um lead…", Rodar na mão),
  # a próxima reunião aberta do lead.
  def reuniao_em
    return @reuniao_em if defined?(@reuniao_em)

    iso = gatilho('inicio')
    @reuniao_em = iso.present? ? Time.zone.parse(iso) : proxima_reuniao
  end

  # Quem marcou/remarcou/cancelou (o usuário do painel; Cal.com = ninguém) — dono da tarefa e da atividade, como no código.
  def quem_marcou
    id = gatilho('quem_marcou_id')
    return if id.blank? || lead.nil?

    lead.account.users.find_by(id: id)
  end

  private

  def contato = lead&.contact || conversa&.contact

  # locais (l, c, r): `&.` repetido na mesma variável conta 1 vez só na complexidade do Rubocop
  def dados_lead
    l = lead
    c = contato
    r = l&.closer || l&.sdr
    nome = c&.name.presence || l&.name
    {
      'nome' => nome.to_s.split.first, 'nome_completo' => nome, 'telefone' => c&.phone_number,
      'responsavel' => r&.name, 'responsavel_id' => r&.id
    }
  end

  def dados_funil
    l = lead
    {
      'etapa' => l&.lead_stage&.name, 'etapa_id' => l&.lead_stage_id,
      'tese' => l&.thesis&.name, 'tese_id' => l&.thesis_id,
      'origem' => l&.source, 'canal' => l&.channel, 'valor' => l&.value&.to_f,
      'prioridade' => l&.lead_priority&.name
    }
  end

  def dados_conversa
    {
      'caixa' => conversa&.inbox&.name, 'caixa_id' => conversa&.inbox_id,
      'status' => conversa&.status, 'etiquetas' => conversa ? conversa.label_list.to_a : []
    }
  end

  def dados_gatilho
    gatilho = execucao.contexto['gatilho'] || {}
    DO_GATILHO.index_with { |chave| gatilho[chave] }
  end

  # {reuniao_de_pe}: a mesma regra do lembrete do código (Ramon::Fluxos::Reunioes.reuniao_aberta?), na hora do passo.
  # ponytail: 1 consulta por passo em fluxo de lead (a próxima reunião); cachear se virar gargalo.
  def dados_reuniao
    inicio = lead && reuniao_em
    return { 'reuniao_de_pe' => nil } unless inicio

    { 'reuniao_de_pe' => Ramon::Fluxos::Reunioes.reuniao_aberta?(lead, inicio) ? 'sim' : 'nao' }
  end

  def proxima_reuniao
    return if lead.nil?

    lead.lead_tasks.open_tasks.where(kind: 'meeting', due_at: Time.current..).minimum(:due_at)
  end

  # preencher_campo grava em custom_attributes['campos'] (Passos::Lead)
  def campos_livres
    campos = lead&.custom_attributes&.dig('campos')
    campos.is_a?(Hash) ? campos : {}
  end

  # Checklist da tese (LeadDocs): conta só o que a equipe confirmou ('recebido');
  # sugestão da IA (doc_sugestao) não conta. Sem checklist → nil ("igual sim" dá não).
  def dados_docs
    lista = lead&.doc_checklist || []
    faltam = lista.reject { |doc| doc[:status] == 'recebido' }
    completos = faltam.empty? ? 'sim' : 'nao'
    { 'documentos_completos' => (completos if lista.any?), 'documentos_faltantes' => faltam.pluck(:title).join(', ') }
  end
end
