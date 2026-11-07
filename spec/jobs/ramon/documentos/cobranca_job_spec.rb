require 'rails_helper'

# Cobrança da etapa Documentos (spec §7): o job roda a cada 15 min e faz o passo que o relógio diz, gravando a marca no lead.
# Data relativa (próxima segunda, 10h em SP): spec com data fixa vence (lição de 15/10).
RSpec.describe Ramon::Documentos::CobrancaJob do
  let(:zona) { Time.find_zone!('America/Sao_Paulo') }
  let(:segunda) { zona.now.next_occurring(:monday).change(hour: 10) }
  let(:account) { create(:account) }
  let(:sdr) { create(:user, account: account, role: :agent) }
  let(:documentos) { Ramon::EtapasPosVenda.criar!(account).first }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
  end
  let(:conversa) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:tese) { create(:thesis, account: account, name: 'Tese Spec Cobrança') }
  let(:lead) { create(:lead, account: account, thesis: tese, sdr: sdr, name: 'Maria da Silva') }

  around { |exemplo| travel_to(segunda) { exemplo.run } }

  before do
    create(:thesis_item, thesis: tese, section: 'documento', title: 'CNIS completo')
    allow(Ramon::NtfyPushJob).to receive(:perform_later)
  end

  def em_documentos(**estado)
    cobranca = estado.transform_keys(&:to_s).transform_values(&:iso8601)
    lead.update_columns(conversation_id: conversa.id, lead_stage_id: documentos.id, # rubocop:disable Rails/SkipsModelValidations
                        custom_attributes: { 'documentos_cobranca' => cobranca })
  end

  def cliente_escreveu(quando)
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, created_at: quando)
  end

  def rodar(chave: 'on') = with_modified_env(RAMON_ETAPA_DOCUMENTOS: chave) { described_class.perform_now }
  def marcas = lead.reload.custom_attributes['documentos_cobranca']
  def historico = lead.lead_activities.where(kind: 'documentos').pluck(:to_value)
  def enviadas = conversa.messages.outgoing.where(private: false)
  def notas_de_handoff = conversa.messages.where(private: true).select { |m| m.content_attributes[Ramon::Documentos::Handoff::MARCA] }

  it 'abertura ao entrar, com a janela aberta: uma mensagem e a marca; rodar de novo não repete (Review Focus 4)', :aggregate_failures do
    cliente_escreveu(segunda - 1.hour)
    em_documentos(entrou_em: segunda - 1.minute)

    2.times { rodar }

    expect(enviadas.count).to eq(1)
    expect(enviadas.last.content).to include('Oi, Maria!', '- CNIS completo')
    expect(marcas['abertura_em']).to be_present
    expect(historico).to eq(['Cobrança: enviou a apresentação (texto livre, na janela de 24 h)'])
    expect(LlmChamada.where(lead_id: lead.id).pluck(:funcao, :model, :custo_usd))
      .to eq([['whatsapp_documentos', 'texto livre', BigDecimal('0.0068')]])
  end

  it 'fora do horário comercial sai cedo, sem olhar lead nenhum' do
    em_documentos(entrou_em: segunda - 1.minute)
    allow(Ramon::Documentos::Relogio).to receive(:proximo_passo)

    travel_to(segunda.change(hour: 20)) # sem bloco: já estamos dentro do travel_to do around
    rodar

    expect(Ramon::Documentos::Relogio).not_to have_received(:proximo_passo)
  end

  it 'conversa com uma pessoa (silêncio ou travado já passados para a equipe) nem entra na conta' do
    em_documentos(entrou_em: segunda - 1.minute)
    conversa.update!(status: :open)
    allow(Ramon::Documentos::Relogio).to receive(:proximo_passo)

    rodar

    expect(Ramon::Documentos::Relogio).not_to have_received(:proximo_passo)
  end

  it 'chave desligada: nada acontece', :aggregate_failures do
    em_documentos(entrou_em: segunda - 1.minute)
    rodar(chave: nil)
    expect(enviadas).to be_empty
    expect(marcas).not_to have_key('abertura_em')
  end

  it 'Review Focus 3: lead que saiu de Documentos não recebe a cobrança pendente', :aggregate_failures do
    cliente_escreveu(segunda - 1.hour)
    em_documentos(entrou_em: segunda - 1.minute)
    lead.update_columns(lead_stage_id: account.lead_stages.find_by(label: Ramon::EtapaDeGanho::FECHADO).id) # rubocop:disable Rails/SkipsModelValidations

    rodar

    expect(enviadas).to be_empty
    expect(marcas).not_to have_key('abertura_em')
  end

  it 'conversa com uma pessoa (aberta) ou checklist completo: nada sai' do
    em_documentos(entrou_em: segunda - 1.minute)
    conversa.update!(status: :open)
    rodar
    conversa.update!(status: :pending)
    lead.update_columns(custom_attributes: lead.custom_attributes.merge('doc_status' => { tese.thesis_items.first.id.to_s => 'recebido' })) # rubocop:disable Rails/SkipsModelValidations
    rodar

    expect(enviadas).to be_empty
  end

  it 'janela fechada e a caixa sem o modelo aprovado: o lembrete não sai e vira silêncio (a conversa vai para a equipe)',
     :aggregate_failures do
    sexta = segunda - 3.days # abertura sexta às 15h: as 3 h úteis vencem segunda às 8h
    cliente_escreveu(sexta)
    em_documentos(entrou_em: sexta + 5.hours, abertura_em: sexta + 5.hours)

    rodar

    expect(enviadas).to be_empty
    expect(marcas).to include('lembrete_1_em', 'silencio_em')
    expect(conversa.reload).to be_open
    expect(notas_de_handoff.map(&:content)).to contain_exactly(a_string_including('silêncio'))
    expect(historico).to match(['Cobrança: o lembrete 1 não saiu: janela de 24 h fechada e a caixa sem o modelo aprovado',
                                a_string_starting_with('Cobrança: silêncio —').and(a_string_ending_with('A conversa foi para a equipe.'))])
    expect(LlmChamada.where(lead_id: lead.id)).to be_empty
  end

  it 'acompanhamento: respondeu, 1 dia útil sem documento novo: sino ao SDR e a IA segue', :aggregate_failures do
    sexta = segunda - 3.days
    em_documentos(entrou_em: sexta, abertura_em: sexta)
    cliente_escreveu(sexta + 1.hour)

    rodar

    aviso = Notification.find_by(user: sdr, notification_type: 'ramon_fluxo_aviso')
    expect(aviso.meta['label']).to include('Maria da Silva', 'sem avanço', 'CNIS completo')
    expect(Ramon::NtfyPushJob).to have_received(:perform_later).with(lead.id, title: satisfy { |t| t.exclude?('Maria') }, body: anything)
    expect(conversa.reload).to be_pending
    expect(marcas).to have_key('acompanhamento_em')
  end

  it 'travado: 2 dias úteis sem documento novo depois do acompanhamento: a conversa vai para a equipe', :aggregate_failures do
    quinta = segunda - 4.days
    em_documentos(entrou_em: quinta, abertura_em: quinta, acompanhamento_em: quinta + 1.day)
    cliente_escreveu(quinta + 1.hour)

    rodar

    expect(conversa.reload).to be_open
    expect(notas_de_handoff.map(&:content)).to contain_exactly(a_string_including('travado'))
    expect(marcas).to have_key('travado_em')
  end
end
