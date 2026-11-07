require 'rails_helper'

# A IA passou a conversa para uma pessoa com o lead em Documentos (spec §6): quem assume é o SDR (online), senão o closer.
RSpec.describe Ramon::Documentos::Handoff do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
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

  def offline!(user) = account.account_users.find_by(user: user).update!(availability: :offline)

  it 'SDR offline: vai para o closer online, sem incomodar os admins', :aggregate_failures do
    admin
    offline!(sdr)
    handoff
    expect(conversa.reload.assignee).to eq(closer)
    expect(avisados).to eq([closer.id])
  end

  it 'os dois offline: fica com o SDR (alguém precisa ser dono) e avisa também os admins (Review Focus 3)', :aggregate_failures do
    admin
    offline!(sdr)
    offline!(closer)
    handoff
    expect(conversa.reload.assignee).to eq(sdr)
    expect(avisados).to contain_exactly(sdr.id, admin.id)
  end

  def do_cliente(quando) = create(:message, account: account, conversation: conversa, message_type: :incoming, created_at: quando)

  def nota_da_ia(texto, quando, tool: false)
    create(:message, account: account, conversation: conversa, message_type: :outgoing, private: true, content: texto,
                     created_at: quando, content_attributes: tool ? { described_class::MARCA => true } : {})
  end

  it 'a nota leva o motivo da tool de handoff depois da última mensagem do cliente; rascunho da IA não vira motivo' do
    do_cliente(2.minutes.ago)
    nota_da_ia('Cliente disse que não tem o laudo', 1.minute.ago, tool: true)
    nota_da_ia('RASCUNHO: resposta segurada', 30.seconds.ago)
    handoff
    expect(notas.last).to include('Motivo: Cliente disse que não tem o laudo', 'CNIS completo')
  end

  it 'sem nota da tool depois da última mensagem do cliente (freio, cota, falha): passagem automática' do
    nota_da_ia('motivo de outra vez', 2.minutes.ago, tool: true)
    do_cliente(1.minute.ago)
    handoff
    expect(notas.last).to include('passagem automática').and(exclude('motivo de outra vez'))
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
