# Migração única (idempotente) dos modos do copiloto para o Perfil da IA: a coluna inboxes.ramon_copiloto_modo vira
# perfil de tese/caixa em account.settings['ia_atendimento'] e copiloto_modo da conversa vira Pausa (spec 2026-10-17, Migração).
module Ramon::PerfilIa::Migracao
  ANTIGAS = %w[copiloto_modo copiloto_modo_antes_roteiro].freeze
  # Modo antigo da caixa → base do perfil. 'manual' e vazio não geram nada (a caixa segue o padrão); 'manual' com assistente
  # na caixa vai para descartadas (o Perfil não tem "IA desligada": quem desliga é o Assistente → Caixas).
  BASES = { 'piloto_ate_qualificacao' => 'cautelosa', 'piloto_ate_reuniao' => 'equilibrada', 'piloto_ate_contrato' => 'acelerada',
            'piloto_total' => 'acelerada' }.freeze
  # Modo da conversa (e o guardado antes do roteiro) → Pausa (piloto_* e vazio = não havia Pausa). Todo 'rascunho' vira Pausa,
  # com ou sem carimbo copiloto_limite.
  PAUSA_DO_MODO = { 'manual' => 'pausada', 'rascunho' => 'rascunho' }.freeze
  DESLIGAR = 'desligar o assistente em Assistente → Caixas'.freeze
  FILTRO = "custom_attributes ? 'copiloto_modo' OR custom_attributes ? 'copiloto_modo_antes_roteiro'".freeze

  def self.rodar(account)
    chave = Ramon::PerfilIa::CHAVE
    gravado = (account.settings || {})[chave]
    config = gravado.deep_dup || {}
    resultado = { padrao: config.key?('padrao') ? 'mantido' : 'gravado', caixas: 0, teses: 0, descartadas: [] }
    config['padrao'] ||= Ramon::PerfilIa::INICIAL.deep_dup
    account.inboxes.find_each { |inbox| migrar_caixa(inbox, config, resultado) }
    account.update!(settings: (account.settings || {}).merge(chave => config)) if config != gravado
    resultado.merge(migrar_conversas(account))
  end

  def self.cfg_do_modo(modo)
    case modo
    when 'rascunho' then Ramon::PerfilIa::INICIAL.deep_merge('permissoes' => { 'logistica' => 'r' })
    when 'piloto_limitado' then Ramon::PerfilIa::INICIAL.deep_dup
    when *BASES.keys then { 'base' => BASES[modo] }
    end
  end
  private_class_method :cfg_do_modo

  # Caixa com tese → perfil da tese (se ainda não tem); sem tese → perfil da caixa. Quem já tem perfil fica e o modo é descartado.
  def self.migrar_caixa(inbox, config, resultado)
    modo = inbox.read_attribute(:ramon_copiloto_modo)
    return resultado[:descartadas] << descarte(inbox, modo, DESLIGAR) if modo == 'manual' && Ramon::PerfilIa.com_ia?(inbox)

    cfg = cfg_do_modo(modo)
    gravar_caixa(inbox, modo, cfg, config, resultado) if cfg
  end

  def self.gravar_caixa(inbox, modo, cfg, config, resultado)
    tese_id = inbox.read_attribute(:ramon_thesis_id)
    tipo = tese_id ? 'teses' : 'caixas'
    id = (tese_id || inbox.id).to_s
    destino = (config[tipo] ||= {})
    if destino.key?(id)
      # perfil igual ao que o modo geraria = rodada anterior, não é descarte
      resultado[:descartadas] << descarte(inbox, modo, tese_id ? 'tese já tinha perfil' : 'caixa já tinha perfil') if destino[id] != cfg
    else
      destino[id] = cfg
      resultado[tipo.to_sym] += 1
    end
  end

  def self.descarte(inbox, modo, motivo) = { caixa: inbox.id, modo: modo, motivo: motivo }
  private_class_method :migrar_caixa, :gravar_caixa, :descarte

  # Um update! por conversa (o audited registra, desejado). Acabou a chave antiga, sai do filtro: rodar de novo não acha nada.
  def self.migrar_conversas(account)
    contagem = { conversas_pausadas: 0, conversas_rascunho: 0 }
    account.conversations.where(FILTRO).find_each do |conversa|
      attrs = conversa.custom_attributes
      pausa = PAUSA_DO_MODO[attrs['copiloto_modo']]
      contagem[:conversas_pausadas] += 1 if pausa == 'pausada'
      contagem[:conversas_rascunho] += 1 if pausa == 'rascunho'
      novos = attrs.except(*ANTIGAS)
      novos[Ramon::PerfilIa::PAUSA] = pausa if pausa
      novos[Ramon::PerfilIa::PAUSA_ANTES] = PAUSA_DO_MODO[attrs['copiloto_modo_antes_roteiro']] if attrs.key?('copiloto_modo_antes_roteiro')
      conversa.update!(custom_attributes: novos)
    end
    contagem
  end
  private_class_method :migrar_conversas
end
