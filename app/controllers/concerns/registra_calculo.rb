# Histórico de cálculos (tela Cálculos): todo cálculo que roda vira registro.
# Guarda o CNIS já processado junto dos parâmetros, pra reabrir o cálculo no
# estado exato sem reanexar o PDF — o PDF em si continua fora do servidor.
module RegistraCalculo
  extend ActiveSupport::Concern

  private

  # Chamar DEPOIS do render, como o persistir_especiais do painel: histórico é
  # registro, nunca pode derrubar o cálculo que o advogado já está vendo.
  def registrar_calculo(tipo)
    Calculo.create!(
      account: Current.account, lead: @lead, user: Current.user, tipo: tipo,
      segurado_nome: nome_do_segurado, segurado_cpf: @lead.cnis&.dig('segurado_cpf'),
      der: permitted[:der].presence,
      snapshot: { 'params' => permitted.to_h, 'cnis' => @lead.cnis }
    )
  rescue StandardError => e
    Rails.logger.warn("[calculo] não registrou o histórico: #{e.class} #{e.message}")
  end

  # Cliente do hub manda no nome (é o cadastro); sem contato, vale o cabeçalho
  # do CNIS — é o que existe no cálculo rápido, que nasce sem cliente.
  def nome_do_segurado
    @lead.contact&.name.presence || @lead.cnis&.dig('segurado_nome')
  end
end
