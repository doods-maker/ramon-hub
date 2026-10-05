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
    @dados ||= dados_lead.merge(dados_conversa).merge(
      'texto' => execucao.contexto.dig('gatilho', 'texto')
    ).merge(execucao.contexto['vars'] || {})
  end

  def interpolar(texto)
    texto.to_s.gsub(/\{(\w+)\}/) { dados.key?(Regexp.last_match(1)) ? dados[Regexp.last_match(1)].to_s : Regexp.last_match(0) }
  end

  private

  def contato = lead&.contact || conversa&.contact

  def dados_lead
    responsavel = lead&.closer || lead&.sdr
    nome = contato&.name.presence || lead&.name
    {
      'nome' => nome.to_s.split.first, 'nome_completo' => nome, 'telefone' => contato&.phone_number,
      'etapa' => lead&.lead_stage&.name, 'etapa_id' => lead&.lead_stage_id,
      'tese' => lead&.thesis&.name, 'tese_id' => lead&.thesis_id,
      'origem' => lead&.source, 'canal' => lead&.channel, 'valor' => lead&.value&.to_f,
      'prioridade' => lead&.lead_priority&.name,
      'responsavel' => responsavel&.name, 'responsavel_id' => responsavel&.id
    }
  end

  def dados_conversa
    {
      'caixa' => conversa&.inbox&.name, 'caixa_id' => conversa&.inbox_id,
      'status' => conversa&.status, 'etiquetas' => conversa ? conversa.label_list.to_a : []
    }
  end
end
