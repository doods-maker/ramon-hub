require 'rails_helper'

RSpec.describe Ramon::DossiePassagemTexto do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.order(:position).first }
  let(:thesis) { create(:thesis, account: account, name: 'Auxílio-acidente') }
  let(:contact) do
    create(:contact, account: account, name: 'João Carlos', cpf: '52998224725', phone_number: '+5548991234567',
                     data_nascimento: Date.new(1968, 5, 14))
  end

  around do |example|
    with_modified_env(FRONTEND_URL: 'https://hub.example.com') { example.run }
  end

  it 'monta o texto puro no formato do jurídico, com BRL e datas brasileiras' do
    recebido = create(:thesis_item, thesis: thesis, section: 'documento', title: 'RG e CPF')
    create(:thesis_item, thesis: thesis, section: 'documento', title: 'Laudo')
    create(:thesis_item, thesis: thesis, section: 'objecao', title: 'É caro', content: 'Só paga se ganhar.')
    lead = create(:lead, account: account, lead_stage: stage, contact: contact, thesis: thesis,
                         dcb_em: Date.new(2023, 3, 12), source: 'lp-auxilio',
                         custom_attributes: {
                           'doc_status' => { recebido.id.to_s => 'recebido' },
                           'utm' => { 'utm_campaign' => 'aux' },
                           'ultima_simulacao' => { 'atrasados' => 38_400, 'mensal' => 1412.5, 'honorario_valor' => 11_520,
                                                   'em' => '2026-10-01T15:00:00Z' }
                         })
    lead.lead_notes.create!(account: account, body: 'Rascunho: oi João!')

    texto = described_class.new(lead: lead).perform

    expect(texto).to start_with("DOSSIÊ DE PASSAGEM — João Carlos\n\nCLIENTE\n- Nome: João Carlos\n- CPF: 529.982.247-25\n" \
                                "- Nascimento: 14/05/1968\n- Telefone: +55 (48) 99123-4567")
    expect(texto).to include("CASO\n- Tese: Auxílio-acidente\n- Benefício: não informado\n- DCB: 12/03/2023")
    expect(texto).to include("SIMULAÇÃO\n- atrasados ~R$ 38.400,00\n- benefício mensal estimado (valor de hoje) ~R$ 1.412,50\n" \
                             "- honorário ~R$ 11.520,00\n- em 01/10/2026")
    expect(texto).to include("DOCUMENTOS\n- Recebidos: RG e CPF\n- Pendentes: Laudo (pendente)")
    expect(texto).to include("CONTRATO\n- Não gerado", "CNIS\n- não anexado", "REUNIÃO\n- não registrada")
    expect(texto).to end_with("FICHA\n- https://hub.example.com/app/accounts/#{account.id}/ramon/lead/#{lead.id}/dossie")
    expect(texto).not_to include('#', '**', 'É caro', 'utm', 'Rascunho', 'lp-auxilio')
  end

  it 'descreve o contrato assinado, a prescrição correndo e a reunião registrada' do
    lead = create(:lead, account: account, lead_stage: stage, contact: contact, dcb_em: 6.years.ago.to_date,
                         benefit_monthly_value: 1412, reuniao_resultado: 'qualificada',
                         reuniao_registrada_em: Time.zone.parse('2026-10-04 15:00'),
                         custom_attributes: { 'zapsign' => { 'status' => 'signed', 'assinado_em' => '2026-10-04T15:00:00Z' } })

    texto = described_class.new(lead: lead).perform

    expect(texto).to include('- Prescrição: 12 parcelas já prescritas · prescrevendo R$ 1.412,00/mês')
    expect(texto).to include("CONTRATO\n- Assinado em 04/10/2026")
    expect(texto).to include("REUNIÃO\n- Resultado: Qualificada\n- Data: 04/10/2026\n- Ata: não informado")
  end

  it 'mostra contrato enviado aguardando assinatura e prescrição futura' do
    lead = create(:lead, account: account, lead_stage: stage, dcb_em: 59.months.ago.to_date,
                         custom_attributes: { 'zapsign' => { 'criado_em' => '2026-10-02T12:00:00Z' } })

    texto = described_class.new(lead: lead).perform

    expect(texto).to include('- Enviado em 02/10/2026, aguardando assinatura')
    expect(texto).to include('- Prescrição: prescreve em 1 mês')
  end
end
