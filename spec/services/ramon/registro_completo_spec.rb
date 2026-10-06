require 'rails_helper'

RSpec.describe Ramon::RegistroCompleto do
  let(:account) { create(:account) }
  let(:sdr) { create(:user, account: account, role: :agent) }
  let(:outro) { create(:user, account: account, role: :agent) }
  let(:stage) { account.lead_stages.find_by(name: 'Novo') }
  let(:thesis) { create(:thesis, account: account) }
  let(:contact) { create(:contact, account: account, cpf: '52998224725', data_nascimento: Date.new(1970, 3, 2)) }
  let(:lead) { create(:lead, account: account, lead_stage: stage, sdr: sdr, contact: contact, thesis: thesis) }

  def marcas
    lead.lead_activities.where(kind: 'registro_completo')
  end

  def nota(user)
    lead.lead_notes.create!(account: account, user: user, body: 'Conversei, tem CAT e laudo.')
  end

  it 'grava a atividade quando o SDR escreve a nota (com tese, CPF e nascimento)', :aggregate_failures do
    expect { nota(outro) }.not_to(change(marcas, :count))
    nota(sdr)

    expect(marcas.count).to eq(1)
    expect(marcas.first.user_id).to eq(sdr.id)
  end

  it 'grava uma vez só' do
    nota(sdr)
    nota(sdr)
    lead.update!(thesis: create(:thesis, account: account))

    expect(marcas.count).to eq(1)
  end

  it 'completa pelo contato: CPF/nascimento preenchidos depois da nota' do
    contact.update!(data_nascimento: nil)
    nota(sdr)
    expect { contact.update!(data_nascimento: Date.new(1970, 3, 2)) }.to change(marcas, :count).from(0).to(1)
  end

  it 'completa pela tese escolhida depois' do
    lead.update!(thesis: nil)
    nota(sdr)
    expect { lead.update!(thesis: thesis) }.to change(marcas, :count).from(0).to(1)
  end

  it 'saída de Fechado grava contrato_cancelado com o won_at antigo', :aggregate_failures do
    fechado = account.lead_stages.find_by(is_won: true)
    lead.update!(lead_stage: fechado)
    ganho_em = lead.reload.won_at
    lead.update!(lead_stage: stage)

    cancelado = lead.lead_activities.find_by(kind: 'contrato_cancelado')
    expect(cancelado).to be_present
    expect(Time.zone.parse(cancelado.from_value).to_i).to eq(ganho_em.to_i)
  end
end
