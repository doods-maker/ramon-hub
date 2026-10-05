# frozen_string_literal: true

# Texto único de passagem ao jurídico: o mesmo no "Copiar dossiê" da ficha, na
# nota automática do ganho e (por link da ficha) no caso criado no AdvBox.
# Texto puro — WhatsApp e AdvBox mostram Markdown cru —, títulos em maiúsculas
# e itens com "- ". Fica de fora o que é interno do comercial: objeções, UTM,
# triagem e notas (rascunhos de mensagem e a própria nota 📋).
class Ramon::DossiePassagemTexto
  NAO_INFORMADO = 'não informado'
  ZONA = 'America/Sao_Paulo'
  RESULTADOS = { 'qualificada' => 'Qualificada', 'nao_qualificada' => 'Não qualificada' }.freeze

  def initialize(lead:, passagem: nil)
    @lead = lead
    @dados = passagem || Ramon::DossiePassagem.new(lead: lead).perform
  end

  def perform
    blocos = [
      ["DOSSIÊ DE PASSAGEM — #{@dados[:nome]}"], cliente, caso, contrato, advbox, drive, cnis,
      simulacao, reuniao, documentos, pendencias, ['FICHA', "- #{@dados[:ficha_url]}"]
    ]
    blocos.map { |linhas| linhas.join("\n") }.join("\n\n")
  end

  private

  def cliente
    ['CLIENTE', item('Nome', @dados[:nome]), item('CPF', cpf(@dados[:cpf])),
     item('Nascimento', data(@dados[:nascimento])), item('Telefone', telefone(@dados[:telefone]))]
  end

  def caso
    ['CASO', item('Tese', @dados[:tese]), item('Benefício', @dados[:beneficio]),
     item('DCB', data(@dados[:dcb_em])), item('Prescrição', prescricao)]
  end

  # Mesmas frases do painel do lead (chip de prescrição).
  def prescricao
    presc = @dados[:prescription]
    return nil if presc.nil?

    perdidas = presc[:lost_installments]
    return "prescreve em #{presc[:months_to_cliff]} #{presc[:months_to_cliff] == 1 ? 'mês' : 'meses'}" unless perdidas.positive?

    mensal = @dados[:benefit_monthly_value]
    ["#{perdidas} parcelas já prescritas", mensal && "prescrevendo #{brl(mensal)}/mês"].compact.join(' · ')
  end

  def contrato
    ['CONTRATO', "- #{contrato_status(@dados[:contrato])}"]
  end

  def contrato_status(zapsign)
    return 'Não gerado' if zapsign.blank?

    case zapsign['status']
    when 'signed' then com_data('Assinado', zapsign['assinado_em'])
    when 'refused' then com_data('Recusado', zapsign['recusado_em'])
    when 'cancelado' then 'Cancelado'
    else "Enviado em #{data(zapsign['criado_em']) || NAO_INFORMADO}, aguardando assinatura"
    end
  end

  def com_data(rotulo, valor)
    valor ? "#{rotulo} em #{data(valor)}" : rotulo
  end

  def advbox
    ['ADVBOX', "- #{advbox_status(@dados[:advbox] || {})}"]
  end

  def advbox_status(adv)
    return "Caso ##{adv['lawsuits_id']} criado no fechamento" if adv['lawsuits_id']
    return 'Falha ao criar o caso no AdvBox' if adv['erro']

    'caso ainda não criado'
  end

  def drive
    ['DRIVE', "- #{@dados[:drive_url] || 'pasta ainda não criada'}"]
  end

  def cnis
    resumo = @dados[:cnis]
    return ['CNIS', '- não anexado'] if resumo.nil?

    partes = ["#{resumo[:competencias]} competências", "#{resumo[:vinculos]} vínculos", resumo[:sexo] && "sexo #{resumo[:sexo]}"]
    ['CNIS', "- #{partes.compact.join(' · ')}"]
  end

  def simulacao
    sim = @dados[:simulacao]
    return ['SIMULAÇÃO', '- nenhuma simulação'] if sim.nil?

    ['SIMULAÇÃO', estimado('atrasados', sim['atrasados']),
     estimado('benefício mensal estimado (valor de hoje)', sim['mensal']),
     estimado('honorário', sim['honorario_valor']), sim['em'] && "- em #{data(sim['em'])}"].compact
  end

  def estimado(rotulo, valor)
    "- #{rotulo} ~#{brl(valor)}" unless valor.nil?
  end

  def reuniao
    reu = @dados[:reuniao]
    return ['REUNIÃO', '- não registrada'] if reu.nil?

    ['REUNIÃO', item('Resultado', RESULTADOS[reu[:resultado]]), item('Data', data(reu[:registrada_em])),
     item('Ata', reu[:ata_resumo])]
  end

  def documentos
    return ['DOCUMENTOS', '- sem checklist (tese não definida)'] if docs.empty?

    recebidos, pendentes = docs.partition { |doc| doc[:status] == 'recebido' }
    ['DOCUMENTOS', item('Recebidos', recebidos.pluck(:title).join('; ').presence, 'nenhum'),
     item('Pendentes', pendentes.map { |doc| "#{doc[:title]} (#{doc[:status]})" }.join('; ').presence, 'nenhum')]
  end

  def pendencias
    tarefa = @lead.lead_tasks.open_tasks.order(:due_at).first
    proximo = tarefa && [tarefa.title, data_hora(tarefa.due_at)].compact.join(' — ')
    faltando = docs.count { |doc| doc[:status] != 'recebido' }
    ['PENDÊNCIAS', item('Próximo passo', proximo, 'nenhuma tarefa aberta'),
     item('Documentos faltando', faltando.positive? ? faltando.to_s : nil, 'nenhum')]
  end

  def docs
    @docs ||= @lead.doc_checklist
  end

  def item(rotulo, valor, vazio = NAO_INFORMADO)
    "- #{rotulo}: #{valor.presence || vazio}"
  end

  def brl(valor)
    ActiveSupport::NumberHelper.number_to_currency(valor.to_f, unit: 'R$ ', separator: ',', delimiter: '.', format: '%u%n')
  end

  def cpf(valor)
    digitos = valor.to_s.gsub(/\D/, '')
    return valor.presence if digitos.length != 11

    "#{digitos[0, 3]}.#{digitos[3, 3]}.#{digitos[6, 3]}-#{digitos[9, 2]}"
  end

  # +5548991234567 → +55 (48) 99123-4567 (celular com 9 ou fixo com 8 dígitos)
  def telefone(valor)
    digitos = valor.to_s.gsub(/\D/, '')
    return valor.presence unless digitos.start_with?('55') && [12, 13].include?(digitos.length)

    numero = digitos[4..]
    "+55 (#{digitos[2, 2]}) #{numero[0..-5]}-#{numero[-4..]}"
  end

  # Date (DCB, nascimento) fica como está; data-hora (ISO ou Time) vai pro fuso
  # do escritório antes de virar dd/mm/aaaa.
  def data(valor)
    momento(valor)&.strftime('%d/%m/%Y')
  end

  def data_hora(valor)
    momento(valor)&.strftime('%d/%m/%Y %H:%M')
  end

  def momento(valor)
    return nil if valor.blank?
    return Date.iso8601(valor) if valor.is_a?(String) && valor.length == 10
    return valor if valor.instance_of?(Date)

    (valor.is_a?(String) ? Time.zone.parse(valor) : valor)&.in_time_zone(ZONA)
  end
end
