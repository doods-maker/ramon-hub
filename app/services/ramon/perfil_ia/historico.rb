# Histórico do Perfil da IA (Registro de ações, tipo "ia"): as linhas de auditoria da Account que mexeram no Perfil
# (ia_atendimento), nos limites gerais (ia_limites) ou no teto em US$. Para cada linha, o que mudou em cada alvo
# ("BPC/LOAS: marcar reunião rascunho → sozinha" — a frase sai na tela, com i18n) e o Desfazer de um alvo só.
class Ramon::PerfilIa::Historico
  CHAVES = [Ramon::PerfilIa::CHAVE, Ramon::IaLimites::CHAVE, Ramon::IaGastoAlerta::CHAVE_TETO].freeze
  # A linha da Account entra se alguma das CHAVES ficou diferente entre o antes e o depois do settings.
  SQL = "(#{CHAVES.map { |k| "audits.audited_changes #> '{settings,0,#{k}}' IS DISTINCT FROM audits.audited_changes #> '{settings,1,#{k}}'" }
                .join(' OR ')})".freeze
  SECAO = { 'tese' => 'teses', 'caixa' => 'caixas' }.freeze
  LIMITES = 'limites'.freeze

  def initialize(account)
    @account = account
  end

  def linhas = Audited.audit_class.where(auditable_type: 'Account', auditable_id: @account.id).where(SQL)

  # [{ alvo:, nome_alvo:, campo:, acao_ou_etapa:, de:, para: }] — campo: segue_padrao | base | marcador | permissao |
  # gatilho | limite. Permissão no valor efetivo (sozinha/rascunho/nunca); com troca de base, o que mudou por cima dela.
  def mudancas(audit)
    antes, depois = settings(audit)
    perfis(Hash(antes[Ramon::PerfilIa::CHAVE]), Hash(depois[Ramon::PerfilIa::CHAVE])) + limites(antes, depois)
  end

  # Regrava o valor de antes da linha só naquele alvo, pelo mesmo caminho de escrita (vira outra linha de auditoria).
  # Linha de outra conta ou que não é do tipo ia = RecordNotFound (404); valor de antes que não vale mais = ArgumentError.
  def desfazer!(audit_id, alvo)
    audit = linhas.find(audit_id)
    raise ArgumentError, 'este alvo não mudou nesta linha' if mudancas(audit).none? { |m| m[:alvo] == alvo }

    antes, depois = settings(audit)
    alvo == LIMITES ? desfazer_limites!(antes, depois) : desfazer_perfil!(alvo, Hash(antes[Ramon::PerfilIa::CHAVE]))
  end

  private

  def settings(audit) = Array(audit.audited_changes['settings']).values_at(0, 1).map { |s| s.is_a?(Hash) ? s : {} }

  def perfis(antes, depois)
    alvos = ['padrao'] + SECAO.flat_map { |tipo, secao| (chaves(antes[secao]) | chaves(depois[secao])).map { |id| "#{tipo}:#{id}" } }
    alvos.flat_map do |alvo|
      de, para = [antes, depois].map { |perfil| cfg_de(perfil, alvo) }
      next [] if de == para

      campos(de, para).map { |m| { alvo: alvo, nome_alvo: nome_alvo(alvo), **m } }
    end
  end

  def chaves(secao) = secao.is_a?(Hash) ? secao.keys : []

  # cfg bruto do alvo; o padrão sem nada gravado é o INICIAL.
  def cfg_de(perfil, alvo)
    tipo, id = alvo.split(':')
    bruto = id ? perfil[SECAO.fetch(tipo)].try(:[], id) : perfil['padrao'] || Ramon::PerfilIa::INICIAL
    bruto if bruto.is_a?(Hash)
  end

  def campos(cfg_antes, cfg_depois)
    return [{ campo: 'segue_padrao', de: cfg_antes.nil?, para: cfg_depois.nil? }] if cfg_antes.nil? || cfg_depois.nil?

    velho, novo = [cfg_antes, cfg_depois].map { |cfg| perfil(cfg) }
    return diferencas(velho, novo) if velho.base == novo.base

    [{ campo: 'base', de: velho.base, para: novo.base }] + diferencas(perfil('base' => novo.base), novo)
  end

  def diferencas(ref, novo)
    lista = []
    lista << { campo: 'marcador', de: nome_marcador(ref.marcador), para: nome_marcador(novo.marcador) } if ref.marcador != novo.marcador
    Ramon::PerfilIa::ACOES.each do |acao|
      de, para = [ref, novo].map { |p| p.permissao(acao).to_s }
      lista << { campo: 'permissao', acao_ou_etapa: acao, de: de, para: para } if de != para
    end
    lista + gatilhos(ref, novo)
  end

  def gatilhos(ref, novo)
    etapas.filter_map do |etapa|
      de, para = [ref, novo].map { |p| p.gatilhos(etapa) }
      next if de.sort == para.sort

      { campo: 'gatilho', acao_ou_etapa: etapa.name, de: nomes_gatilhos(de), para: nomes_gatilhos(para) }
    end
  end

  def nomes_gatilhos(lista) = lista.filter_map { |chave| Ramon::PerfilIa::GATILHOS.dig(chave, 'nome') }

  # Perfil efetivo de um cfg (a mesma conta da IA: base, Marcador na Trilha, permissões e gatilhos).
  # ponytail: um PerfilIa por cfg (1 SELECT das Etapas cada); juntar se a página de 50 linhas pesar
  def perfil(cfg) = Ramon::PerfilIa.new(nil, Lead.new(account: @account), 'historico', Ramon::PerfilIa.normalizar(cfg), :historico)

  def etapas = @etapas ||= @account.lead_stages.where(is_won: false, is_lost: false).to_a

  # _inicio/_fim vão como estão (a tela traduz); Etapa vai pelo nome.
  def nome_marcador(chave)
    etapas.find { |e| Ramon::PerfilIa.chave_da_etapa(e) == chave }&.name || chave
  end

  def nome_alvo(alvo)
    tipo, id = alvo.split(':')
    return if id.nil?

    @nomes ||= { 'tese' => @account.theses.pluck(:id, :name).to_h, 'caixa' => @account.inboxes.pluck(:id, :name).to_h }
    @nomes.dig(tipo, id.to_i)
  end

  # nil = o valor de sempre (a tela mostra "padrão").
  def limites(antes, depois)
    de, para = [antes, depois].map { |s| limites_de(s) }
    teto = Ramon::IaGastoAlerta::CHAVE_TETO
    lista = (de.keys | para.keys).filter_map { |k| { campo: 'limite', acao_ou_etapa: k, de: de[k], para: para[k] } if de[k] != para[k] }
    lista << { campo: 'limite', acao_ou_etapa: 'teto_usd', de: antes[teto], para: depois[teto] } if antes[teto] != depois[teto]
    lista.map { |m| { alvo: LIMITES, nome_alvo: nil, **m } }
  end

  # Tese/caixa sem cfg antes = volta a seguir o padrão (nil tira o alvo); o padrão sem nada antes = o INICIAL.
  def desfazer_perfil!(alvo, antes)
    tipo, id = alvo.split(':')
    alvos = id ? { SECAO.fetch(tipo) => { id => cfg_de(antes, alvo) } } : { 'padrao' => cfg_de(antes, alvo).deep_dup }
    Ramon::PerfilIa.gravar!(@account, alvos)
  end

  # Só as chaves que mudaram nesta linha voltam (validadas de novo); as mudadas depois, em outras chaves, ficam.
  def desfazer_limites!(antes, depois)
    de, para = [antes, depois].map { |s| limites_de(s) }
    mudadas = (de.keys | para.keys).reject { |k| de[k] == para[k] }
    settings = Hash(@account.settings)
    extra = { Ramon::IaLimites::CHAVE => limites_de(settings).except(*mudadas).merge(Ramon::IaLimites.validados!(de.slice(*mudadas).compact)) }
    teto = Ramon::IaGastoAlerta::CHAVE_TETO
    extra[teto] = Ramon::IaLimites.teto!(antes[teto]) if antes[teto] != depois[teto]
    @account.update!(settings: settings.merge(extra))
  end

  def limites_de(settings) = settings[Ramon::IaLimites::CHAVE].is_a?(Hash) ? settings[Ramon::IaLimites::CHAVE] : {}
end
