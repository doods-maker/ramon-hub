require 'rails_helper'

RSpec.describe Ramon::JanelaWhatsappJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:sdr) { create(:user, account: account) }
  # 13:00 UTC = 10:00 em São Paulo, horário de aviso. Data relativa: spec com data fixa vence (lição de 15/10).
  let(:agora) { Time.current.utc.beginning_of_day + 13.hours }

  before { create(:lead, account: account, conversation: conversation, sdr: sdr, name: 'Maria da Silva') }

  def cliente_escreveu(atras, anuncio: false)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: agora - atras,
                     content_attributes: anuncio ? { referral: { source_type: 'ad', ctwa_clid: 'abc' } } : {})
  end

  def avisos = Notification.where(user: sdr, notification_type: 'ramon_fluxo_aviso')

  def rodar(quando = agora) = travel_to(quando) { Ramon::JanelaWhatsappJob.perform_now }

  it 'avisa o SDR uma vez quando faltam até 4h para fechar a janela de 24h' do
    cliente_escreveu(21.hours)

    2.times { rodar }

    expect(avisos.count).to eq(1)
    expect(avisos.first.meta['label']).to include('a janela grátis do WhatsApp fecha em')
  end

  it 'não avisa quando a janela ainda está longe de fechar' do
    cliente_escreveu(10.hours)
    rodar

    expect(avisos.count).to eq(0)
  end

  it 'não avisa quando a janela já fechou' do
    cliente_escreveu(30.hours)
    rodar

    expect(avisos.count).to eq(0)
  end

  it 'na conversa que veio de anúncio vale a janela de 72h desde a mensagem do anúncio' do
    cliente_escreveu(70.hours, anuncio: true)
    cliente_escreveu(50.hours)

    rodar

    expect(avisos.count).to eq(1)
  end

  it 'não avisa lead de anúncio no meio das 72h' do
    cliente_escreveu(21.hours, anuncio: true)

    rodar

    expect(avisos.count).to eq(0)
  end

  it 'na última rodada (20h) avisa também o prazo que vence de madrugada' do
    noite = Time.current.utc.beginning_of_day + 23.hours # 20h em São Paulo
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     created_at: noite - 18.hours) # a janela fecha às 02h, fora das 4h de antecedência

    rodar(noite)

    expect(avisos.count).to eq(1)
  end
end
