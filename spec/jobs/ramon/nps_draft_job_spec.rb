require 'rails_helper'

RSpec.describe Ramon::NpsDraftJob do
  let(:account) { create(:account) }
  let(:lead) do
    create(:lead, account: account, name: 'Maria da Silva', custom_attributes: { 'advbox' => { 'lawsuits_id' => 9 } })
  end

  it 'cria a nota RASCUNHO com a pergunta 0-10 e placeholder do Google, gravando só a chave nps' do
    with_modified_env(RAMON_GOOGLE_REVIEW_URL: nil) do
      described_class.perform_now(lead.id)
    end

    note = lead.lead_notes.find_by("body LIKE 'RASCUNHO%'")
    expect(note.body).to include('de 0 a 10')
    expect(note.body).to include('[link do Google Meu Negócio]')
    expect(note.body).to include('Maria')
    expect(lead.reload.custom_attributes.dig('nps', 'pedido_em')).to be_present
    expect(lead.custom_attributes['advbox']).to eq('lawsuits_id' => 9)
  end

  it 'usa o link real quando RAMON_GOOGLE_REVIEW_URL está configurado' do
    with_modified_env(RAMON_GOOGLE_REVIEW_URL: 'https://g.page/ramon') do
      described_class.perform_now(lead.id)
    end

    expect(lead.lead_notes.find_by("body LIKE 'RASCUNHO%'").body).to include('https://g.page/ramon')
  end

  it 'não pede de novo na mesma fase (guard pedido_em)' do
    lead.update!(custom_attributes: { 'nps' => { 'pedido_em' => Time.current.iso8601 } })

    expect { described_class.perform_now(lead.id) }.not_to change(LeadNote, :count)
  end

  it 'fase êxito pede mesmo com o pedido comercial já feito (uma vez por fase)' do
    lead.update!(custom_attributes: { 'nps' => { 'pedido_em' => Time.current.iso8601 } })

    expect { described_class.perform_now(lead.id, fase: 'exito') }.to change(LeadNote, :count).by(1)
    expect(lead.reload.custom_attributes['nps'].keys).to include('pedido_em', 'pedido_exito_em')
  end

  it 'não repete o pedido de êxito (guard pedido_exito_em)' do
    lead.update!(custom_attributes: { 'nps' => { 'pedido_exito_em' => Time.current.iso8601 } })

    expect { described_class.perform_now(lead.id, fase: 'exito') }.not_to change(LeadNote, :count)
  end
end
