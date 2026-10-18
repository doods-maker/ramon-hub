require 'rails_helper'

RSpec.describe Ramon::ZapsignLeadStatusJob do
  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account, role: :administrator) } # o sino vai pra quem vê o lead
  let(:lead) do
    create(:lead, account: account, custom_attributes: {
             'zapsign' => { 'doc_token' => 'doc-1', 'sign_url' => 'https://x', 'template_name' => 'Contrato' }
           })
  end

  it 'assinado: grava status/data, histórico e sino — sem marcar ganho (peça zapsign_ganho off)' do
    doc = { 'status' => 'signed', 'signers' => [{ 'signed_at' => '2026-10-03T14:00:00Z' }] }
    allow(Ramon::ZapsignClient).to receive(:doc).with('doc-1').and_return(doc)
    allow(Ramon::Fluxos::Disparo).to receive(:externo).and_return([])

    described_class.perform_now(lead.id, 'doc-1')

    zapsign = lead.reload.custom_attributes['zapsign']
    expect(zapsign).to include('status' => 'signed', 'assinado_em' => '2026-10-03T14:00:00Z', 'doc_token' => 'doc-1')
    expect(lead.won_at).to be_nil
    expect(lead.lead_activities.pluck(:kind)).to include('zapsign_signed')
    expect(Notification.where(notification_type: 'ramon_contract_status', user: user, primary_actor: lead)).to exist
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_assinado', lead).once # só os fluxos comuns
  end

  it 'assinado com a peça zapsign_ganho on: marca o lead como ganho' do
    Ramon::FunilAutomatico.mudar!(account, 'zapsign_ganho', 'on')
    allow(Ramon::ZapsignClient).to receive(:doc).with('doc-1').and_return('status' => 'signed', 'signers' => [])
    allow(Ramon::Fluxos::Disparo).to receive(:externo).and_return([])

    described_class.perform_now(lead.id, 'doc-1')

    expect(lead.reload.won_at).to be_present
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_assinado', lead).once
  end

  it 'falha na regra do funil não derruba o job nem os fluxos' do
    allow(Ramon::ZapsignClient).to receive(:doc).and_return('status' => 'signed', 'signers' => [])
    allow(Ramon::Fluxos::Disparo).to receive(:externo).and_return([])
    allow(Ramon::FunilAutomatico).to receive(:executar).and_raise(StandardError, 'boom')
    Ramon::FunilAutomatico.mudar!(account, 'zapsign_ganho', 'on')

    expect { described_class.perform_now(lead.id, 'doc-1') }.not_to raise_error
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_assinado', lead).once
  end

  it 'recusado: grava status e data da recusa' do
    allow(Ramon::ZapsignClient).to receive(:doc).and_return('status' => 'refused', 'signers' => [])
    allow(Ramon::Fluxos::Disparo).to receive(:externo).and_return([])

    described_class.perform_now(lead.id, 'doc-1')

    expect(lead.reload.custom_attributes['zapsign']).to include('status' => 'refused', 'recusado_em' => be_present)
    expect(lead.lead_activities.pluck(:kind)).to include('zapsign_refused')
    expect(Ramon::Fluxos::Disparo).to have_received(:externo).with('contrato_recusado', lead).once
  end

  it 'doc trocado ("Gerar de novo") ou já registrado não consulta nem notifica' do
    allow(Ramon::ZapsignClient).to receive(:doc)

    described_class.perform_now(lead.id, 'doc-antigo')
    lead.update!(custom_attributes: { 'zapsign' => { 'doc_token' => 'doc-1', 'status' => 'cancelado' } })
    described_class.perform_now(lead.id, 'doc-1')

    expect(Ramon::ZapsignClient).not_to have_received(:doc)
    expect(Notification.where(notification_type: 'ramon_contract_status')).not_to exist
  end

  it 'pendente no ZapSign não muda nada' do
    allow(Ramon::ZapsignClient).to receive(:doc).and_return('status' => 'pending')

    described_class.perform_now(lead.id, 'doc-1')

    expect(lead.reload.custom_attributes['zapsign']).not_to have_key('status')
  end
end
