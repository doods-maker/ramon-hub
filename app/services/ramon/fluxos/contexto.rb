# O que um passo enxerga: o alvo (lead/conversa) recarregado a cada passo + variáveis
# da execução. `dados` alimenta condições e o `{chave}` dos textos.
class Ramon::Fluxos::Contexto
  attr_reader :execucao

  def initialize(execucao)
    @execucao = execucao
  end

  def lead = @lead ||= execucao.lead

  def conversa = @conversa ||= execucao.conversa

  def ensaio? = execucao.ensaio

  def dados
    @dados ||= dados_lead.merge(dados_funil).merge(dados_conversa).merge(
      'texto' => execucao.contexto.dig('gatilho', 'texto')
    ).merge(execucao.contexto['vars'] || {})
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
end
