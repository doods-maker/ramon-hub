require 'rails_helper'

RSpec.describe Ramon::DossiePassagem do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.order(:position).first }

  around do |example|
    with_modified_env(FRONTEND_URL: 'https://hub.example.com') { example.run }
  end

  describe '.ficha_url' do
    it 'aponta pra rota da ficha (ramon_lead_dossie) com a conta do lead' do
      lead = create(:lead, account: account, lead_stage: stage)
      expect(described_class.ficha_url(lead))
        .to eq("https://hub.example.com/app/accounts/#{account.id}/ramon/lead/#{lead.id}/dossie")
    end
  end

  describe '.ata_resumo' do
    it 'fica com o parágrafo do Resumo, sem markdown' do
      ata = "## Participantes\n- Dr. Ramon\n\n## Resumo\nCliente **trouxe** o laudo.\n\n## Decisões\n- Protocolar"
      expect(described_class.ata_resumo(ata)).to eq('Cliente trouxe o laudo.')
    end

    it 'usa o texto todo quando a ata não segue o formato e devolve nil sem ata' do
      expect(described_class.ata_resumo('Conversa rápida, sem pauta.')).to eq('Conversa rápida, sem pauta.')
      expect(described_class.ata_resumo(nil)).to be_nil
    end
  end

  describe '#perform' do
    it 'junta contrato, AdvBox, Drive, CNIS, simulação e reunião do que o lead já guarda' do
      contact = create(:contact, account: account, name: 'João', cpf: '529.982.247-25', phone_number: '+5548999990000',
                                 data_nascimento: Date.new(1968, 5, 14))
      lead = create(:lead, account: account, lead_stage: stage, contact: contact, dcb_em: 3.years.ago.to_date,
                           benefit_monthly_value: 1412, reuniao_resultado: 'qualificada',
                           reuniao_registrada_em: 1.day.ago,
                           cnis: { 'entrada' => { 'segurado' => { 'sexo' => 'M' }, 'competencias' => [1, 2, 3] },
                                   'vinculos' => [{}, {}] },
                           custom_attributes: {
                             'zapsign' => { 'status' => 'signed', 'assinado_em' => '2026-10-04T13:00:00Z', 'doc_token' => 'x' },
                             'advbox' => { 'lawsuits_id' => 222 },
                             'drive' => { 'pasta_id' => 'abc' },
                             'ultima_simulacao' => { 'atrasados' => 38_400, 'mensal' => 1412, 'em' => '2026-10-01T12:00:00Z' }
                           })
      reuniao = Reuniao.create!(account: account, lead: lead, status: 'pronta', ata: "## Resumo\nTrouxe o laudo.")

      passagem = described_class.new(lead: lead).perform

      expect(passagem).to include(nome: 'João', nascimento: Date.new(1968, 5, 14), telefone: '+5548999990000',
                                  drive_url: 'https://drive.google.com/drive/folders/abc')
      expect(passagem[:contrato]).to eq('status' => 'signed', 'assinado_em' => '2026-10-04T13:00:00Z')
      expect(passagem[:advbox]).to eq('lawsuits_id' => 222)
      expect(passagem[:cnis]).to eq(competencias: 3, vinculos: 2, sexo: 'M')
      expect(passagem[:simulacao]).to include('atrasados' => 38_400, 'mensal' => 1412)
      expect(passagem[:reuniao]).to include(resultado: 'qualificada', reuniao_id: reuniao.id, ata_resumo: 'Trouxe o laudo.')
      expect(passagem[:prescription]).to include(lost_installments: 0, months_to_cliff: 24)
    end

    it 'devolve nil no que falta, sem quebrar em lead sem contato' do
      lead = create(:lead, account: account, lead_stage: stage)

      passagem = described_class.new(lead: lead).perform

      expect(passagem.values_at(:cpf, :contrato, :advbox, :drive_url, :cnis, :simulacao, :reuniao, :prescription))
        .to all(be_nil)
      expect(passagem[:nome]).to eq(lead.name)
    end
  end
end
