require 'rails_helper'

RSpec.describe Ramon::JanelaWhatsappJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:sdr) { create(:user, account: account) }
  let!(:lead) { create(:lead, account: account, conversation: conversation, sdr: sdr, name: 'Maria da Silva') }
  # 13:00 UTC = 10:00 em São Paulo, horário de aviso. Data relativa: spec com data fixa vence (lição de 15/10).
  let(:agora) { Time.current.utc.beginning_of_day + 13.hours }

  def cliente_escreveu(atras)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: agora - atras)
  end

  def avisos = Notification.where(user: sdr, notification_type: 'ramon_fluxo_aviso')

  def rodar = travel_to(agora) { Ramon::JanelaWhatsappJob.perform_now }

  it 'avisa o SDR uma vez quando faltam até 4h para fechar a janela de 24h' do
    cliente_escreveu(21.hours)

    2.times { rodar }

    expect(avisos.count).to eq(1)
    expect(avisos.first.meta['label']).to include('a janela grátis do WhatsApp fecha às')
  end

  it 'não avisa quando a janela ainda está longe de fechar ou já fechou' do
    cliente_escreveu(10.hours)
    rodar
    conversation.messages.delete_all
    cliente_escreveu(30.hours)
    rodar

    expect(avisos.count).to eq(0)
  end

  it 'no lead de anúncio vale a janela de 72h desde a 1ª mensagem' do
    lead.update!(custom_attributes: { 'meta_referral' => { 'ctwa_clid' => 'abc' } })
    cliente_escreveu(70.hours)
    cliente_escreveu(50.hours)

    rodar

    expect(avisos.count).to eq(1)
  end

  it 'não avisa lead de anúncio no meio das 72h' do
    lead.update!(custom_attributes: { 'meta_referral' => { 'ctwa_clid' => 'abc' } })
    cliente_escreveu(21.hours)

    rodar

    expect(avisos.count).to eq(0)
  end
end
