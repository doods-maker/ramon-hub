# Esquema da colheita por tese (spec 2026-11-09-colheita-por-tese). Dado puro:
# cada bloco é o modelo JSON que a IA preenche. Folha nil = texto livre,
# [] = lista de texto, "a|b|c" = escolha uma, Hash / [Hash] = aninhado.
module Ramon::Colheita::Esquema # rubocop:disable Metrics/ModuleLength -- o módulo é dado (blocos por tese)
  NUCLEO = %w[cliente beneficios fechamento outras_teses_sinal].freeze

  SIM_NAO = 'sim|nao|nao_sabe'.freeze
  TRATAMENTO = { 'tipo' => 'cirurgia|conservador|internacao|medicacao', 'onde' => nil, 'quando' => nil }.freeze
  ACIDENTE = {
    'data' => nil, 'tipo' => 'trabalho|trajeto|doenca_trabalho|outra_natureza', 'descricao' => nil, 'lesao' => nil,
    'cat_emitida' => SIM_NAO, 'empregador_na_epoca' => nil
  }.freeze
  SEQUELA = {
    'descricao' => nil, 'cid' => nil, 'consolidada' => 'sim|em_tratamento|nao_sabe', 'limitacao_concreta' => nil,
    'tratamentos' => [TRATAMENTO]
  }.freeze

  BLOCOS = {
    # --- núcleo (§1)
    'cliente' => {
      'nome_completo' => nil, 'cpf' => nil, 'rg' => nil, 'nascimento' => nil, 'nacionalidade' => nil, 'estado_civil' => nil,
      'profissao' => nil, 'endereco' => nil, 'whatsapp' => nil, 'renda_aproximada' => nil,
      'representante' => { 'nome' => nil, 'parentesco' => nil, 'motivo' => nil }
    },
    'beneficios' => [{
      'nb' => nil, 'especie' => 'B31|B91|B94|B32|B92|B36|B87|B88|B80|B41|B42|B21|outro', 'der' => nil, 'dib' => nil, 'dcb' => nil,
      'situacao' => 'cessado|ativo|indeferido|nao_requerido', 'prorrogacao_pedida' => SIM_NAO, 'motivo' => nil
    }],
    'fechamento' => {
      'honorario_apresentado' => nil, 'simulacao_mostrada' => nil, 'contrato_assinado' => nil,
      'motivo_nao_assinatura' => nil, 'objecoes' => [], 'sensibilidades' => nil
    },
    'outras_teses_sinal' => [{ 'tese' => nil, 'motivo' => nil }],

    # --- previdenciários e assistenciais (§3)
    'segurado' => {
      'regime_na_data' => 'carteira|rural_pesca|autonomo_mei|facultativa|servidor|desempregado',
      'servidor_rpps' => SIM_NAO, 'ultima_contribuicao' => nil, 'mais_de_120' => SIM_NAO,
      'desemprego_comprovado' => 'seguro|sine|outro_meio|nao'
    },
    'saude' => {
      'doencas' => [{ 'nome' => nil, 'cid' => nil, 'diagnostico_em' => nil }],
      'tratamentos' => [TRATAMENTO], 'laudo_disponivel' => 'sim|nao|parcial'
    },
    'incapacidade' => {
      'funcao_exigencias' => nil, 'parou_em' => nil, 'afastado_hoje' => 'afastado|trabalhando|desempregado',
      'limitacoes_atuais' => nil, 'evolucao' => 'piorando|estavel|melhorando', 'prognostico' => nil,
      'escolaridade' => nil, 'pericia_desconsiderou' => nil, 'ligada_ao_trabalho' => SIM_NAO
    },
    'dependencia' => {
      'precisa_ajuda' => 'sim|nao|parcial', 'atividades' => [], 'desde' => nil, 'quem_cuida' => nil,
      'laudo_cuidador' => SIM_NAO
    },
    'assistencial' => {
      'cadunico' => { 'inscrito' => SIM_NAO, 'atualizado' => SIM_NAO },
      'impedimento' => { 'o_que_limita' => nil, 'desde' => nil, 'barreiras' => nil },
      'moradores' => [{ 'parentesco' => nil, 'idade' => nil, 'renda_mensal' => nil, 'fonte' => nil }],
      'renda_total_declarada' => nil,
      'rendas_excluidas' => [{ 'parentesco' => nil, 'tipo' => nil }],
      'gastos_saude' => [{ 'item' => nil, 'valor_mensal' => nil }],
      'moradia' => { 'tipo' => 'propria|alugada|cedida', 'aluguel' => nil }
    },
    'maternidade' => {
      'fato' => 'gestante|parto|natimorto|adocao|guarda_adocao|aborto', 'data_fato' => nil, 'semanas' => nil,
      'ja_recebeu' => nil,
      'trabalho_na_data' => 'domestica|empregada_mei|intermitente|mei|autonoma|facultativa|desempregada|rural_pesca|empregada_empresa',
      'facultativa_dona_casa' => nil,
      'rural' => { 'atividade' => 'lavoura|pesca', 'onde' => nil, 'regime_familiar' => nil, 'desde' => nil,
                   'documentos_que_tem' => [] },
      'demitida_gestante' => 'sim|nao'
    },
    'ir' => {
      'fonte' => 'inss|rpps|outro', 'tipo_renda' => 'aposentadoria|pensao', 'valor_mensal' => nil, 'outras_fontes' => [],
      'doenca_lista' => { 'doenca' => nil, 'enquadramento' => 'lista|nao_tem_certeza' },
      'situacao_doenca' => 'em_tratamento|controlada|curada',
      'ja_pediu' => { 'onde' => 'inss|receita', 'quando' => nil, 'resultado' => nil }
    },

    # --- auxílio-acidente (§4)
    'qualificacao' => {
      'aposentado' => nil, 'qualidade_segurado_epoca' => nil, 'qualidade_segurado_como' => nil,
      'recebeu_auxilio_doenca' => nil
    },
    'acidente' => ACIDENTE,
    'sequela' => SEQUELA,

    # --- trabalhistas (§5)
    'contrato' => {
      'empregador' => nil, 'funcao' => nil, 'carteira' => 'assinada|sem_carteira|pj_mei', 'admissao' => nil,
      'ainda_trabalha' => 'sim|afastado_inss|ferias|saiu', 'saida_em' => nil,
      'tipo_saida' => 'sem_justa_causa|justa_causa|pediu|acordo|fim_contrato',
      'salario' => { 'registrado' => nil, 'real' => nil, 'por_fora' => 'sim|nao' },
      'jornada' => { 'horario' => nil, 'dias_semana' => nil, 'horas_extras' => 'sim|nao', 'pagas_certo' => 'sim|nao' },
      'processo_anterior' => 'nao|sim_julgado|arquivado_sem_julgamento',
      'provas_disponiveis' => [], 'testemunhas' => [{ 'nome' => nil, 'relacao' => nil }]
    },
    'queixas' => [{
      'hipotese' => 'salario_atrasado|fgts_sem_deposito|verbas_rescisorias|horas_extras|salario_por_fora|desvio_acumulo|' \
                    'insalubridade_periculosidade|descontos|assedio|ferias|beneficio_cortado|transferencia|acidente_doenca',
      'descricao' => nil, 'desde' => nil, 'ainda_acontece' => 'sim|nao', 'periodo' => nil
    }],
    'vinculo' => {
      'pf_ou_pj' => 'pessoa_fisica|pj|mei', 'pessoalidade' => nil,
      'habitualidade' => { 'dias_semana' => nil, 'tempo_servico' => nil }, 'domestico' => 'sim|nao',
      'pagamento' => { 'forma' => 'mes|dia|hora|tarefa|comissao', 'valor' => nil, 'meio' => 'pix|dinheiro|recibo' },
      'subordinacao' => { 'ordens_de_quem' => nil, 'horario_fixo' => nil, 'justificava_faltas' => nil, 'punicoes' => nil },
      'avaliacao' => nil
    },
    'responsabilidade' => {
      'culpa_fatos' => nil, 'atividade_risco' => nil, 'nexo_doenca' => nil, 'aso' => nil,
      'dispensado_apos_alta' => nil, 'gastos' => nil
    }
  }.freeze

  # Em ordem: 25% antes de B32 ("grande invalidez"); trabalhista de acidente antes de qualquer regex de acidente.
  TESES = [
    [:acrescimo25, /25\s*%|grande invalidez/i, %w[saude dependencia]],
    [:b31, /B31|incapacidade tempor/i, %w[segurado saude incapacidade]],
    [:b32, /B32|incapacidade permanente/i, %w[segurado saude incapacidade dependencia]],
    [:trab_acidente, /trabalhista.*(acidente|doen)/i, %w[contrato acidente sequela responsabilidade]],
    [:trab_rescisao, /rescis[aã]o indireta/i, %w[contrato queixas]],
    [:trab_vinculo, /v[ií]nculo/i, %w[contrato vinculo]],
    [:trab_suprimido, /direito suprimido/i, %w[contrato queixas]],
    [:b36, /aux[ií]lio-acidente/i, %w[qualificacao acidente sequela]],
    [:bpc, /BPC|LOAS/i, %w[saude assistencial]],
    [:maternidade, /sal[aá]rio-maternidade/i, %w[segurado maternidade]],
    [:ir, /isen[cç][aã]o de IR|imposto de renda/i, %w[saude ir]]
  ].freeze

  def self.tese(thesis_name)
    TESES.find { |_, regex, _| thesis_name.to_s.match?(regex) }&.first
  end

  def self.blocos_para(thesis_name)
    chave = tese(thesis_name)
    NUCLEO + (TESES.find { |t, _, _| t == chave }&.last || [])
  end

  def self.modelo_json(thesis_name)
    modelo = BLOCOS.slice(*blocos_para(thesis_name)).merge(
      'confirmar' => ['caminho.do.campo dito de forma incerta'],
      'lacunas' => [{ 'campo' => 'caminho.do.campo', 'como_obter' => 'documento/fonte que resolve' }],
      'checklist_ok' => [123]
    )
    JSON.pretty_generate(modelo)
  end

  # Caminhos de 1º nível (bloco.campo); bloco que é lista de objetos entra inteiro.
  def self.campos(bloco)
    definicao = BLOCOS.fetch(bloco)
    definicao.is_a?(Hash) ? definicao.keys.map { |campo| "#{bloco}.#{campo}" } : [bloco]
  end
end
