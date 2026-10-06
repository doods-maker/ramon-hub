# O que um passo enxerga: o alvo (lead/conversa) recarregado a cada passo + variáveis
# da execução. `dados` alimenta condições e o `{chave}` dos textos.
class Ramon::Fluxos::Contexto
  # o que o gatilho traz e vira variável: {texto} da mensagem, {quando} da reunião,
  # {regra} do evento do ADVBOX, {documento} do anexo casado com o checklist
  DO_GATILHO = %w[texto quando regra documento].freeze

  # chaves que o próprio hub monta em `dados`: preencher_campo recusa (o campo nunca apareceria)
  RESERVADAS = (DO_GATILHO + %w[nome nome_completo telefone responsavel responsavel_id etapa etapa_id tese tese_id origem canal
                                valor prioridade caixa caixa_id status etiquetas documentos_completos documentos_faltantes
                                resposta_ia]).freeze

  attr_reader :execucao

  def initialize(execucao)
    @execucao = execucao
  end

  def lead = @lead ||= execucao.lead

  def conversa = @conversa ||= execucao.conversa

  def ensaio? = execucao.ensaio

  # campos livres primeiro: um campo chamado "nome" nunca pisa no nome do lead
  def dados
    @dados ||= campos_livres.merge(dados_lead, dados_funil, dados_conversa, dados_docs, dados_gatilho,
                                   execucao.contexto['vars'] || {})
  end

  def interpolar(texto)
    texto.to_s.gsub(/\{(\w+)\}/) { dados.key?(Regexp.last_match(1)) ? dados[Regexp.last_match(1)].to_s : Regexp.last_match(0) }
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
