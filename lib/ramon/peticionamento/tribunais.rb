module Ramon::Peticionamento::Tribunais
  MB = 1024 * 1024

  TODOS = {
    'trf4' => { nome: 'TRF4 / JFSC', sistema: 'eproc', limite_bytes: 11 * MB },
    'tjsc' => { nome: 'TJSC', sistema: 'eproc', limite_bytes: 11 * MB },
    'trt12' => { nome: 'TRT12', sistema: 'pje', limite_bytes: 3 * MB }
  }.freeze

  TIPOS = %w[peticao procuracao documento_identificacao comprovante_residencia cnis laudo_medico ppp_ltcat carteira_trabalho
             contrato_honorarios declaracao outro].freeze

  # Rótulos aproximados — conferir no eproc na Fase 2; pje usa os mesmos (ajuste fino na Fase 4).
  ROTULOS = {
    'peticao' => 'PETIÇÃO', 'procuracao' => 'PROCURAÇÃO', 'documento_identificacao' => 'DOCUMENTO DE IDENTIFICAÇÃO',
    'comprovante_residencia' => 'COMPROVANTE DE ENDEREÇO', 'cnis' => 'CNIS', 'laudo_medico' => 'LAUDO', 'ppp_ltcat' => 'PPP',
    'carteira_trabalho' => 'CTPS', 'contrato_honorarios' => 'CONTRATO', 'declaracao' => 'DECLARAÇÃO', 'outro' => 'OUTROS'
  }.freeze

  PALAVRAS = [
    [/peti/, 'peticao'], [/procura/, 'procuracao'], [/\b(rg|cnh)\b|identidade/, 'documento_identificacao'],
    [/residencia|endereco/, 'comprovante_residencia'], [/cnis/, 'cnis'], [/laudo|atestado|exame|prontuario/, 'laudo_medico'],
    [/ppp|ltcat/, 'ppp_ltcat'], [/ctps|carteira/, 'carteira_trabalho'], [/contrato/, 'contrato_honorarios'], [/declara/, 'declaracao']
  ].freeze

  # O rótulo hoje não depende do tribunal; o parâmetro fica para o ajuste fino do pje.
  def self.tipo_no_tribunal(_tribunal, tipo)
    ROTULOS.fetch(tipo.to_s, 'OUTROS')
  end

  def self.sugerir_tipo(nome_arquivo)
    nome = I18n.transliterate(nome_arquivo.to_s).downcase
    PALAVRAS.find { |regex, _| nome.match?(regex) }&.last || 'outro'
  end
end
