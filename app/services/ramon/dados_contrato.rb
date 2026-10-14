# A IA grava os dados do contrato no CONTATO do lead (roteiro F5; decisão do Eduardo 14/10, reverte a pergunta A da F3)
# nos mesmos campos que o "Dados do contrato" do painel e o Ramon::ZapsignContractService leem: contact.name,
# contact.cpf e custom_attributes 'endereco' (hash), 'estado_civil' e 'profissao'. Grava aos poucos: o que vier em
# branco não apaga nada e o endereço soma às chaves que já existem (o painel tem o próprio caminho, que substitui).
# CPF que já é de outro contato da conta não é gravado: a equipe é avisada e a IA passa para humano.
# LGPD: name/cpf entram na trilha do audited (RamonPessoa); o texto para a IA nunca repete o CPF.
module Ramon::DadosContrato
  ENDERECO = %w[cep rua numero complemento bairro cidade uf].freeze
  CAMPOS = (%w[nome cpf estado_civil profissao] + ENDERECO).freeze
  CPF_EM_USO = 'ja esta no cadastro de outra pessoa'.freeze
  # Saem em branco no contrato mas não seguram o envio (os que seguram: ContratoAutomatico::OBRIGATORIOS).
  COMPLEMENTARES = { '{{estado civil}}' => 'estado civil', '{{profissão}}' => 'profissão', '{{bairro}}' => 'bairro' }.freeze

  module_function

  # @return { erro: } | { gravado: [campo], recusado: { campo => motivo }, falta: [..], complementar: [..] }
  def gravar(lead, dados)
    contato = lead.contact
    return { erro: 'Este caso nao tem contato no hub: passe para humano.' } if contato.nil?

    dados = normalizar(dados)
    recusado = {}
    nome!(contato, dados['nome'], recusado)
    cpf!(contato, dados['cpf'], recusado)
    contato.custom_attributes = atributos(contato.custom_attributes || {}, dados)
    contato.save!
    avisar_cpf_em_uso(lead) if recusado['cpf'] == CPF_EM_USO
    { gravado: dados.keys - recusado.keys, recusado: recusado }.merge(faltando(lead.reload))
  rescue ActiveRecord::RecordInvalid => e
    { erro: "Nao gravei: #{e.record.errors.full_messages.to_sentence}" }
  end

  # Só as chaves conhecidas, sem espaços sobrando; em branco sai (não apaga o que já está gravado).
  def normalizar(dados)
    dados.to_h.transform_keys(&:to_s).slice(*CAMPOS).transform_values { |valor| valor.to_s.squish }.compact_blank
  end

  def nome!(contato, nome, recusado)
    return if nome.nil?
    return recusado['nome'] = 'tem uma palavra so - peca o nome completo, como no documento' if nome.split.size < 2

    contato.name = nome
  end

  # A validação do próprio contato (formato + única na conta) decide; recusado, volta o CPF de antes.
  def cpf!(contato, cpf, recusado)
    return if cpf.nil?

    contato.cpf = cpf
    contato.valid?
    erros = contato.errors.details[:cpf].pluck(:error)
    return if erros.empty?

    contato.cpf = contato.cpf_was
    recusado['cpf'] = erros.include?(:taken) ? CPF_EM_USO : 'nao e um CPF valido - confira os numeros com o lead'
  end

  def atributos(attrs, dados)
    endereco = dados.slice(*ENDERECO)
    endereco['uf'] = endereco['uf'].upcase if endereco['uf']
    endereco['cep'] = endereco['cep'].delete('^0-9') if endereco['cep']
    attrs = attrs.merge('endereco' => (attrs['endereco'].is_a?(Hash) ? attrs['endereco'] : {}).merge(endereco)) if endereco.any?
    attrs.merge(dados.slice('estado_civil', 'profissao'))
  end

  # Uma prévia só: os vazios servem para o que segura o contrato e para os complementares.
  def faltando(lead)
    vazios = Ramon::ZapsignContractService.new(lead).preview['faltando']
    { falta: Ramon::ContratoAutomatico.dados_faltando(lead, vazios), complementar: COMPLEMENTARES.slice(*vazios).values }
  end

  def avisar_cpf_em_uso(lead)
    Ramon::AvisoDaIa.avisar(lead, "IA: o CPF que #{lead.name} informou ja esta no cadastro de outra pessoa - confira com ele",
                            "CPF ja cadastrado: #{lead.name}", 'O CPF informado pertence a outro contato da conta.')
  end

  # Texto para a IA (tool registrar_dados_contrato).
  def texto(res)
    return res[:erro] if res[:erro]

    partes = []
    partes << "Gravado no cadastro: #{res[:gravado].join(', ')}." if res[:gravado].any?
    res[:recusado].each { |campo, motivo| partes << "Nao gravei #{campo}: #{motivo}." }
    partes << 'Nao insista no CPF: diga que alguem da equipe confere com ele e passe para humano.' if res[:recusado]['cpf'] == CPF_EM_USO
    partes << (res[:falta].any? ? "Ainda falta para o contrato: #{res[:falta].join(', ')}." : 'Cadastro completo para o contrato.')
    partes << "Se ainda nao souber, pergunte tambem: #{res[:complementar].join(', ')}." if res[:complementar].any?
    partes.join(' ')
  end
end
