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

  # Nome digitado na tela (cálculo rápido de quem ainda não é cliente) vence;
  # depois o cadastro do hub; por fim o cabeçalho do CNIS. Leitura direta de
  # params: é só registro, não mass-assignment.
  def nome_do_segurado
    params[:segurado_nome].presence || @lead.contact&.name.presence || @lead.cnis&.dig('segurado_nome')
  end
end
