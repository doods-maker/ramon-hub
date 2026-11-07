require 'rails_helper'

# A IA passou a conversa para uma pessoa com o lead em Documentos (spec §6): quem assume é o SDR (online), senão o closer.
RSpec.describe Ramon::Documentos::Handoff do
  let(:account) { create(:account) }
  let(:sdr) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:closer) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:documentos) { Ramon::EtapasPosVenda.criar!(account).first }
  let(:tese) { create(:thesis, account: account, name: 'Tese Spec Handoff') }
  let!(:rg) { create(:thesis_item, thesis: tese, section: 'documento', title: 'RG') }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:lead) do
    create(:lead, account: account, thesis: tese, sdr: sdr, closer: closer, name: 'Fulano de Tal',
                  custom_attributes: { 'doc_status' => { rg.id.to_s => 'recebido' } })
  end

  before do
    create(:thesis_item, thesis: tese, section: 'documento', title: 'CNIS completo')
    lead.update_columns(conversation_id: conversa.id, lead_stage_id: documentos.id) # rubocop:disable Rails/SkipsModelValidations
    allow(Ramon::NtfyPushJob).to receive(:perform_later)
  end

  def handoff(chave: 'on') = with_modified_env(RAMON_ETAPA_DOCUMENTOS: chave) { described_class.call(conversa) }
  def avisados = Notification.where(primary_actor: lead, notification_type: 'ramon_fluxo_aviso').pluck(:user_id)
  def notas = conversa.messages.where(private: true).pluck(:content)

  it 'atribui ao SDR online, deixa nota com o que falta e avisa só ele; o push leva só a tese', :aggregate_failures do
    handoff

    expect(conversa.reload.assignee).to eq(sdr)
    expect(notas).to contain_exactly(a_string_including('CNIS completo'))
    expect(notas.first).not_to include('RG')
    expect(avisados).to eq([sdr.id])
    expect(Ramon::NtfyPushJob).to have_received(:perform_later)
      .with(lead.id, title: satisfy { |t| t.include?('Tese Spec Handoff') && t.exclude?('Fulano') },
                     body: satisfy { |b| b.exclude?('Fulano') })
  end

  it 'SDR offline: vai para o closer online' do
    account.account_users.find_by(user: sdr).update!(availability: :offline)
    handoff
    expect(conversa.reload.assignee).to eq(closer)
  end

  it 'a nota leva o motivo que a IA deixou ao passar a conversa' do
    create(:message, account: account, conversation: conversa, message_type: :outgoing, private: true,
                     content: 'Cliente disse que não tem o laudo')
    conversa.messages.last.update_columns(sender_type: 'Captain::Assistant') # rubocop:disable Rails/SkipsModelValidations
    handoff
    expect(notas.last).to include('Cliente disse que não tem o laudo', 'CNIS completo')
  end

  it 'fora de Documentos, ou com a chave desligada, é o handoff de hoje: nada muda', :aggregate_failures do
    handoff(chave: nil)
    lead.update_columns(lead_stage_id: account.lead_stages.find_by(label: 'fase-qualificacao').id) # rubocop:disable Rails/SkipsModelValidations
    handoff

    expect(conversa.reload.assignee).to be_nil
    expect(notas).to be_empty
    expect(avisados).to be_empty
  end
end
