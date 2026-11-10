# Funções puras do planejamento previdenciário: corpo do motor e nomes dos arquivos no Drive.
module Ramon::PlanejamentoPrevidenciario
  module_function

  # cnis = lead.cnis; perfil = Hash string-keyed vindo da tela.
  def payload(cnis, perfil, segurado_nome:, data_calculo: nil)
    entrada = cnis['entrada']
    corpo = {
      segurado: entrada['segurado'], competencias: entrada['competencias'], vinculos: entrada['vinculos'],
      perfil: perfil.to_h.compact_blank.merge('segurado_nome' => segurado_nome)
    }
    corpo[:vinculos_detalhe] = cnis['vinculos'] unless cnis['vinculos'].nil?
    corpo[:data_calculo] = data_calculo unless data_calculo.nil?
    cnis_data = data_iso(cnis['uploaded_at'])
    corpo[:cnis_data] = cnis_data if cnis_data
    corpo
  end

  def nomes(dados, hoje: Date.current)
    nome = dados['nome'].to_s.delete('/\:*?"<>|').squish
    prefixo = dados['turma'].present? ? 'Raio-X Elites' : 'Planejamento previdenciário'
    {
      pasta: "Planejamento previdenciário – #{hoje.strftime('%m.%y')}",
      pdf: "#{prefixo} - #{nome}.pdf",
      memoria: "Memória de cálculo - #{nome}.xlsx"
    }
  end

  def data_iso(valor)
    Date.parse(valor.to_s).iso8601 if valor.present?
  rescue Date::Error
    nil
  end
end
