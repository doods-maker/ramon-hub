# Aplica a decisão (Hash) do observador do funil: cada efeito passa pela chave da peça em Ramon::FunilAutomatico.
# Um método privado por efeito, para as próximas peças (reunião, promessas, pendências) entrarem na sequência de perform.
class Ramon::FunilObservador::Aplicar
  # etapa decidida → [label destino, labels de origem permitidos]
  ETAPAS = { 'qualificacao' => ['fase-qualificacao', %w[fase-novo]],
             'ultima_chance' => ['fase-ultima-chance', %w[fase-reuniao-realizada fase-negociacao]] }.freeze
  TEMPERATURAS = %w[quente morno frio].freeze

  def initialize(lead, decisao)
    @lead = lead
    @decisao = decisao || {}
  end

  def perform
    @lead.reload
    return if @lead.won_at || @lead.lost_at

    mover_etapa
    perder_por_recusa
    gravar_temperatura
  end

  private

  def account = @lead.account

  def mover_etapa
    destino, origens = ETAPAS[@decisao['etapa']]
    return if destino.nil? || origens.exclude?(@lead.lead_stage&.label)

    etapa = account.lead_stages.find_by(label: destino)
    return if etapa.nil? || Ramon::FunilAutomatico.desfeita_recente?(@lead, acao: 'mover_etapa', alvo: etapa.name)

    Ramon::FunilRegras.mover_para_frente(@lead, destino, peca: 'etapa_ia', motivo: @decisao['etapa_motivo'])
  end

  def perder_por_recusa
    recusa = @decisao['perdido']
    return if recusa.blank?

    perdido = account.lead_stages.find_by(is_lost: true)
    return if perdido.nil?

    motivo = recusa['motivo'].presence_in(account.lost_reasons.pluck(:name))
    @lead.with_lock do
      next if @lead.lead_stage.is_won || @lead.lead_stage.is_lost

      Ramon::FunilAutomatico.executar(@lead, peca: 'perdido_recusa', acao: 'perdido', motivo: recusa['frase'] || 'recusa clara',
                                             alvo: motivo || 'recusa', desfazer: desfazer_perdido) do
        Ramon::Roteiro::Efeitos.perder(@lead, motivo)
      end
    end
  end

  def desfazer_perdido
    desfazer = { 'etapa_id' => @lead.lead_stage_id }
    desfazer['modo'] = Ramon::CopilotoModo.of(@lead.conversation) if @lead.conversation
    desfazer
  end

  # Sem FunilAcao (ruído no resumo); só com a peça on — em ensaio não grava.
  def gravar_temperatura
    nivel = @decisao['temperatura']
    return unless TEMPERATURAS.include?(nivel) && Ramon::FunilAutomatico.modo(account, 'temperatura') == 'on'

    @lead.update!(custom_attributes: (@lead.custom_attributes || {}).merge(
      'temperatura' => { 'nivel' => nivel, 'motivo' => @decisao['temperatura_motivo'].to_s.truncate(250), 'em' => Time.current.iso8601 }
    ))
  end
end
