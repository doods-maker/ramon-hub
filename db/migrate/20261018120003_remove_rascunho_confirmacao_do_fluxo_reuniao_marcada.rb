# Confirmação de reunião sempre pelo hub (decisão do dono, 16/10): tira do fluxo "Reunião marcada" já gravado o passo
# "Rascunho de confirmação" (rascunho e versões publicadas), religando as setas. Idempotente: só mexe se o passo estiver lá.
class RemoveRascunhoConfirmacaoDoFluxoReuniaoMarcada < ActiveRecord::Migration[7.1]
  def up
    Fluxo.where(origem: 'usuario', sistema_chave: 'reuniao_marcada').find_each do |fluxo|
      limpo = sem_confirmacao(fluxo.rascunho)
      fluxo.update_columns(rascunho: limpo) if limpo # rubocop:disable Rails/SkipsModelValidations
      fluxo.versoes.find_each do |versao|
        limpo = sem_confirmacao(versao.grafo)
        versao.update_columns(grafo: limpo) if limpo # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end

  def down; end

  private

  # nil se o passo não está lá (nada a fazer); senão o grafo sem ele, com as setas de entrada ligadas à saída dele.
  def sem_confirmacao(grafo) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    alvo = grafo['nos']&.find { |n| n['tipo'] == 'rascunho_texto' && n.dig('config', 'titulo') == 'confirmação de reunião' }
    return unless alvo

    depois = grafo['setas'].find { |s| s['de'] == alvo['id'] }&.fetch('para')
    setas = grafo['setas'].reject { |s| s['de'] == alvo['id'] }
    setas = setas.map { |s| s['para'] == alvo['id'] ? s.merge('para' => depois) : s } if depois
    grafo.merge('nos' => grafo['nos'] - [alvo], 'setas' => setas.reject { |s| s['para'] == alvo['id'] })
  end
end
