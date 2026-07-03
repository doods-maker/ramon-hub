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

  it 'cria a nota de dossiê (sistema) ao ganhar, com tese e documentos' do
    lead.update!(lead_stage: won_stage)
    note = dossiers(lead).last

    expect(note.user).to be_nil
    expect(note.body).to start_with('📋 DOSSIÊ')
    expect(note.body).to include(thesis.name)
    expect(note.body).to include('Documentos (tese):')
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

  it 'trunca o corpo do dossiê em no máximo 1000 caracteres' do
    3.times { |i| lead.lead_notes.create!(account: account, body: "Nota longa #{i} " + ('x' * 900)) }
    lead.update!(lead_stage: won_stage)

    expect(dossiers(lead).last.body.length).to be <= 1000
  end
end
