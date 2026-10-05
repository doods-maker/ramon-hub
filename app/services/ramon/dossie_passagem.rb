# frozen_string_literal: true

# Bloco "Passagem ao jurídico" da ficha: o que o jurídico precisa pra assumir o
# caso — contrato, AdvBox, Drive, CNIS, simulação, reunião — lido do que o hub
# já guarda. Dado que falta vem nil (a ficha mostra "—"; o texto, por extenso).
class Ramon::DossiePassagem
  ATA_RESUMO_MAX = 300

  # Link absoluto da ficha (rota ramon_lead_dossie do front).
  def self.ficha_url(lead)
    "#{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{lead.account_id}/ramon/lead/#{lead.id}/dossie"
  end

  # Ata é markdown do LLM (## Participantes / ## Resumo / ...): fica o parágrafo
  # do Resumo, sem marcação; ata fora do formato vira o começo do texto todo.
  def self.ata_resumo(ata)
    return nil if ata.blank?

    resumo = ata[/^##\s*Resumo[^\n]*\n(.+?)(?=^##|\z)/m, 1].presence || ata
    resumo.gsub(/[#*_>`]/, '').squish.truncate(ATA_RESUMO_MAX)
  end

  def initialize(lead:)
    @lead = lead
    @contact = lead.contact
    @attrs = lead.custom_attributes || {}
  end

  def perform
    cliente.merge(caso).merge(
      contrato: fatia('zapsign', %w[status criado_em assinado_em recusado_em]),
      advbox: fatia('advbox', %w[lawsuits_id erro]),
      drive_url: drive_url,
      cnis: cnis,
      simulacao: fatia('ultima_simulacao', %w[atrasados mensal honorario_valor em]),
      reuniao: reuniao,
      ficha_url: self.class.ficha_url(@lead)
    )
  end

  private

  def cliente
    {
      nome: @contact&.name.presence || @lead.name,
      cpf: @contact&.cpf,
      nascimento: @contact&.data_nascimento,
      telefone: @contact&.phone_number
    }
  end

  def caso
    {
      tese: @lead.thesis&.name,
      beneficio: @lead.benefit_type&.name,
      dcb_em: @lead.dcb_em,
      benefit_monthly_value: @lead.benefit_monthly_value&.to_f,
      prescription: prescription
    }
  end

  def prescription
    presc = @lead.prescription
    return nil if presc.nil?

    presc.merge(
      lost_value: presc[:lost_value]&.to_f,
      months_to_cliff: [Lead::PRESCRIPTION_WINDOW_MONTHS - presc[:months_since_dcb], 0].max
    )
  end

  def fatia(chave, campos)
    (@attrs[chave] || {}).slice(*campos).compact.presence
  end

  def drive_url
    pasta = @attrs.dig('drive', 'pasta_id')
    "https://drive.google.com/drive/folders/#{pasta}" if pasta.present?
  end

  def cnis
    resumo = @lead.cnis_resumo
    return nil if resumo.nil?

    {
      competencias: resumo[:competencias],
      vinculos: resumo[:vinculos],
      sexo: @lead.cnis.dig('entrada', 'segurado', 'sexo')
    }
  end

  def reuniao
    ultima = @lead.reunioes.where.not(ata: [nil, '']).reorder(created_at: :desc).first
    return nil if @lead.reuniao_resultado.blank? && ultima.nil?

    {
      resultado: @lead.reuniao_resultado,
      registrada_em: @lead.reuniao_registrada_em,
      reuniao_id: ultima&.id,
      ata_resumo: ultima && self.class.ata_resumo(ultima.ata)
    }
  end
end
