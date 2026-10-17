# Caminho de escrita do Perfil da IA (a leitura normaliza em silêncio; aqui o que é inválido é recusado).
# Um account.update! só = uma linha de auditoria por save. alvos parcial: seção ausente fica como está.
module Ramon::PerfilIa::Gravacao
  CHAVES_DO_CFG = %w[base marcador permissoes gatilhos].freeze

  def self.gravar!(account, alvos)
    raise ArgumentError, 'corpo inválido' unless alvos.is_a?(Hash)

    etapas = account.lead_stages.where(is_won: false, is_lost: false).map { |e| Ramon::PerfilIa.chave_da_etapa(e) }
    settings = Hash(account.settings)
    atual = Hash(settings[Ramon::PerfilIa::CHAVE])
    novo = atual.merge(alvos.slice('teses', 'caixas').to_h { |tipo, secao| [tipo, mesclar(atual[tipo], tipo, secao, account, etapas)] })
    novo['padrao'] = cfg_valido!(alvos['padrao'], etapas) if alvos.key?('padrao')
    account.update!(settings: settings.merge(Ramon::PerfilIa::CHAVE => novo))
  end

  # Seção atual com os alvos enviados por cima (nil tira o alvo).
  def self.mesclar(atual, tipo, secao, account, etapas)
    escopo = tipo == 'teses' ? account.theses : account.inboxes
    Hash(atual).merge(secao!(secao, tipo, escopo, etapas)).compact
  end

  # { id => cfg | nil }; id de outra conta é recusado.
  def self.secao!(secao, tipo, escopo, etapas)
    raise ArgumentError, "#{tipo} inválido" unless secao.is_a?(Hash)

    secao.to_h do |id, cfg|
      raise ArgumentError, "#{tipo.chomp('s')} #{id} não é desta conta" unless escopo.exists?(id: id.to_s)

      [id.to_s, (cfg_valido!(cfg, etapas) unless cfg.nil?)]
    end
  end

  def self.cfg_valido!(cfg, etapas)
    raise ArgumentError, 'configuração inválida' unless cfg.is_a?(Hash)

    cfg = cfg.slice(*CHAVES_DO_CFG)
    base!(cfg['base']) if cfg.key?('base')
    marcador!(cfg['marcador'], etapas) if cfg.key?('marcador')
    permissoes!(cfg['permissoes']) if cfg.key?('permissoes')
    gatilhos!(cfg['gatilhos'], etapas) if cfg.key?('gatilhos')
    cfg
  end

  def self.base!(base)
    raise ArgumentError, "base desconhecida: #{base}" unless Ramon::PerfilIa::PRONTOS.key?(base)
  end

  def self.marcador!(marcador, etapas)
    return if [Ramon::PerfilIa::INICIO, Ramon::PerfilIa::FIM, *etapas].include?(marcador)

    raise ArgumentError, "marcador desconhecido: #{marcador}"
  end

  def self.permissoes!(permissoes)
    raise ArgumentError, 'permissões inválidas' unless permissoes.is_a?(Hash)

    permissoes.each do |acao, valor|
      raise ArgumentError, "ação desconhecida: #{acao}" unless Ramon::PerfilIa::ACOES.include?(acao)
      raise ArgumentError, "permissão inválida em #{acao}: #{valor}" unless Ramon::PerfilIa::PERMISSOES.key?(valor)
      raise ArgumentError, "#{acao} não aceita nunca" if valor == 'n' && Ramon::PerfilIa::SEM_NUNCA.include?(acao)
    end
  end

  # Gatilho pendente (sem texto) pode estar no cfg: os prontos o trazem; só não entra no prompt.
  def self.gatilhos!(gatilhos, etapas)
    raise ArgumentError, 'gatilhos inválidos' unless gatilhos.is_a?(Hash)

    gatilhos.each do |etapa, lista|
      raise ArgumentError, "etapa desconhecida: #{etapa}" unless etapas.include?(etapa)
      raise ArgumentError, "gatilhos de #{etapa} inválidos" unless lista.is_a?(Array)

      desconhecidos = lista - Ramon::PerfilIa::GATILHOS.keys
      raise ArgumentError, "gatilho desconhecido: #{desconhecidos.first}" if desconhecidos.any?
    end
  end
end
