# Corpo da API da tela "Como a IA atende" (show e update devolvem o mesmo): catálogo + o que está salvo.
class Ramon::PerfilIa::Tela
  # Em que Etapa a linha da ação aparece na tela (citar_honorario aparece em duas).
  ETAPAS_DA_ACAO = {
    'fora_do_horario' => %w[fase-novo],
    'pedir_documentos' => %w[fase-qualificacao], 'desqualificar' => %w[fase-qualificacao],
    'mover_etapa' => %w[fase-qualificacao], 'marcar_reuniao' => %w[fase-qualificacao],
    'citar_honorario' => %w[fase-qualificacao fase-negociacao],
    'logistica' => %w[fase-reuniao-agendada], 'contrato_zapsign' => %w[fase-negociacao]
  }.freeze

  def initialize(account)
    @account = account
  end

  def corpo
    { prontos: Ramon::PerfilIa::PRONTOS, inicial: Ramon::PerfilIa::INICIAL, acoes: acoes, gatilhos: gatilhos,
      etapas: etapas, padrao: Ramon::PerfilIa.cfg_salvo(@account, 'padrao') || Ramon::PerfilIa::INICIAL,
      teses: @account.theses.map { |t| { id: t.id, nome: t.name, cfg: Ramon::PerfilIa.cfg_salvo(@account, 'teses', t.id) } },
      caixas: caixas, limites: Ramon::IaLimites.corpo(@account) }
  end

  private

  def acoes
    Ramon::PerfilIa::ACOES.map do |chave|
      { chave: chave, etapas: ETAPAS_DA_ACAO.fetch(chave), sem_nunca: Ramon::PerfilIa::SEM_NUNCA.include?(chave) }
    end
  end

  def gatilhos
    Ramon::PerfilIa::GATILHOS.map { |chave, g| { chave: chave, nome: g['nome'], pendente: g['texto'].nil? } }
  end

  def etapas
    @account.lead_stages.where(is_won: false, is_lost: false).map { |e| { chave: Ramon::PerfilIa.chave_da_etapa(e), nome: e.name } }
  end

  # Caixa de tese (ramon_thesis_id) segue a tese; só as que têm IA (captain_assistant, enterprise) configuram aqui.
  def caixas
    @account.inboxes.where(ramon_thesis_id: nil).select { |i| i.try(:captain_assistant).present? }.map do |i|
      { id: i.id, nome: i.name, cfg: Ramon::PerfilIa.cfg_salvo(@account, 'caixas', i.id) }
    end
  end
end
