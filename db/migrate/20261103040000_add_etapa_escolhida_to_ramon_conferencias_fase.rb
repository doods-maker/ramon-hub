# Conferência de fases: etapa do ADVBOX escolhida pela equipe na linha ({ etapa, etapa_id, step }), quando não é a sugerida.
class AddEtapaEscolhidaToRamonConferenciasFase < ActiveRecord::Migration[7.1]
  def change
    add_column :ramon_conferencias_fase, :etapa_escolhida, :jsonb
  end
end
