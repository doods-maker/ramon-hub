# Confirmação de reunião sempre pelo hub (decisão do dono, 16/10): tira do fluxo "Reunião marcada" já gravado o passo
# de rascunho nas notas do lead (rascunho e versões publicadas), religando as setas, e atualiza a descrição se for a da seed
# antiga. Idempotente: só mexe se o passo estiver lá; descrição editada pelo usuário fica como está.
class RemoveRascunhoConfirmacaoDoFluxoReuniaoMarcada < ActiveRecord::Migration[7.1]
  # Classes locais: a migração não depende dos models (que mudam).
  Fluxo = Class.new(ActiveRecord::Base) { self.table_name = 'ramon_fluxos' }
  Versao = Class.new(ActiveRecord::Base) { self.table_name = 'ramon_fluxo_versoes' }

  DESCRICOES_ANTIGAS = [
    'Reunião marcada ou remarcada (painel do lead ou Cal.com), no lugar do código (B4.1): atividade, tarefa da reunião, ' \
    'etapa (só para a frente), Closer automático, rascunho de confirmação nas notas do lead, sino para a conta e push. ' \
    'Remarcar refaz a atividade, o rascunho e o sino, sem tarefa nova, etapa ou Closer. ' \
    'Enquanto o selo disser "em sombra", só ensaia: quem faz ainda é o código.',
    'Reunião marcada ou remarcada (painel do lead), no lugar do código (B4.1): atividade, tarefa da reunião, ' \
    'etapa (só para a frente), Closer automático, rascunho de confirmação nas notas do lead, sino para a conta e push. ' \
    'Remarcar refaz a atividade, o rascunho e o sino, sem tarefa nova, etapa ou Closer. ' \
    'Enquanto o selo disser "em sombra", só ensaia: quem faz ainda é o código.'
  ].freeze
  DESCRICAO_NOVA = 'Reunião marcada ou remarcada (painel do lead), no lugar do código (B4.1): atividade, tarefa da reunião, ' \
                   'etapa (só para a frente), Closer automático, sino para a conta e push. ' \
                   'O rascunho de confirmação nas notas é sempre do hub (não está neste desenho). ' \
                   'Remarcar refaz a atividade e o sino, sem tarefa nova, etapa ou Closer. ' \
                   'Enquanto o selo disser "em sombra", só ensaia: quem faz ainda é o código.'.freeze

  def up
    Fluxo.where(origem: 'usuario', sistema_chave: 'reuniao_marcada').find_each do |fluxo|
      limpo = sem_confirmacao(fluxo.rascunho)
      fluxo.update_columns(rascunho: limpo) if limpo # rubocop:disable Rails/SkipsModelValidations
      fluxo.update_columns(descricao: DESCRICAO_NOVA) if DESCRICOES_ANTIGAS.include?(fluxo.descricao) # rubocop:disable Rails/SkipsModelValidations
      Versao.where(fluxo_id: fluxo.id).find_each do |versao|
        limpo = sem_confirmacao(versao.grafo)
        versao.update_columns(grafo: limpo) if limpo # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  # nil se o passo não está lá (nada a fazer); senão o grafo sem ele, com as setas de entrada ligadas à saída dele.
  def sem_confirmacao(grafo) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    alvo = grafo['nos']&.find { |n| n['tipo'] == 'rascunho_texto' && n.dig('config', 'onde') == 'notas_do_lead' }
    return unless alvo

    depois = grafo['setas'].find { |s| s['de'] == alvo['id'] }&.fetch('para')
    setas = grafo['setas'].reject { |s| s['de'] == alvo['id'] }
    setas = setas.map { |s| s['para'] == alvo['id'] ? s.merge('para' => depois) : s } if depois
    grafo.merge('nos' => grafo['nos'] - [alvo], 'setas' => setas.reject { |s| s['para'] == alvo['id'] })
  end
end
