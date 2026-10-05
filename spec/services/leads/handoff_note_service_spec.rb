require 'rails_helper'

RSpec.describe Leads::HandoffNoteService do
  let(:account) { create(:account) }
  let(:won_stage) { account.lead_stages.find_by(is_won: true) }
  let(:active_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }
  let(:thesis) { account.theses.find { |t| t.thesis_items.exists?(section: 'documento') } }
  let(:lead) { create(:lead, account: account, lead_stage: active_stage, thesis: thesis) }

  def dossiers(record)
    record.lead_notes.where('body LIKE ?', "#{described_class::DOSSIER_PREFIX}%")
  end

  it 'cria a nota de dossiê (sistema) ao ganhar, com o texto único de passagem' do
    lead.update!(lead_stage: won_stage)
    note = dossiers(lead).last

    expect(note.user).to be_nil
    expect(note.body).to start_with('📋 DOSSIÊ')
    expect(note.body).to include(thesis.name)
    expect(note.body).to include('DOCUMENTOS')
    expect(note.body).to include("/ramon/lead/#{lead.id}/dossie")
  end

  it 'não duplica o dossiê ao re-salvar um lead já ganho' do
    lead.update!(lead_stage: won_stage)

    expect { lead.update!(name: 'Outro nome') }.not_to(change { dossiers(lead).count })
  end

  it 'cria um novo dossiê ao voltar para ativa e ganhar de novo (fora da janela)' do
    lead.update!(lead_stage: won_stage)
    lead.update!(lead_stage: active_stage)
    travel_to(6.minutes.from_now) { lead.update!(lead_stage: won_stage) }

    expect(dossiers(lead).count).to eq(2)
  end

  it 'não leva as notas do lead pra passagem (rascunhos ficam no comercial)' do
    lead.lead_notes.create!(account: account, body: 'Rascunho: oi, tudo bem?')
    lead.update!(lead_stage: won_stage)

    expect(dossiers(lead).last.body).not_to include('Rascunho')
  end

  it 'texto acima do limite da nota (1000) corta e fecha com o link da ficha' do
    30.times { |i| create(:thesis_item, thesis: thesis, section: 'documento', title: "Documento comprido número #{i}") }
    lead.update!(lead_stage: won_stage)

    body = dossiers(lead).last.body
    expect(body.length).to be <= 1000
    expect(body).to end_with("Texto completo na ficha: #{Ramon::DossiePassagem.ficha_url(lead)}")
  end
end
