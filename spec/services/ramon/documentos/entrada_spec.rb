require 'rails_helper'

RSpec.describe Ramon::Documentos::Entrada do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:sdr) { create(:user, account: account, role: :agent) }
  let(:closer) { create(:user, account: account, role: :agent) }
  let(:documentos) { Ramon::EtapasPosVenda.criar!(account).first }
  let(:tese) { create(:thesis, account: account, name: 'Tese Spec Entrada') }
  let(:conversa) do
    create(:conversation, account: account, status: :open, custom_attributes: { 'ia_pausa' => 'pausada', 'outro' => 'fica' })
  end
  let(:lead) { create(:lead, account: account, thesis: tese, lead_stage: documentos) }

  def avisados = Notification.where(primary_actor: lead, notification_type: 'ramon_fluxo_aviso').pluck(:user_id)
  def historico = lead.lead_activities.where(kind: 'documentos').pluck(:to_value)

  context 'when a conversa é de uma caixa com IA' do
    before do
      lead.update_columns(conversation_id: conversa.id) # rubocop:disable Rails/SkipsModelValidations -- sem atribuir a conversa
      allow(Captain::AssistenteDaConversa).to receive(:para).with(conversa).and_return(Object.new)
    end

    it 'volta para a IA: pendente, sem Pausa, com linha no histórico e sem avisar ninguém', :aggregate_failures do
      described_class.call(lead.reload)

      expect(conversa.reload).to be_pending
      expect(conversa.custom_attributes).to eq('outro' => 'fica')
      expect(historico.size).to eq(1)
      expect(avisados).to be_empty
    end
  end

  context 'without conversa de WhatsApp' do
    it 'avisa o SDR do lead, empurra o push só com a tese e registra no histórico', :aggregate_failures do
      lead.update_columns(sdr_id: sdr.id, closer_id: closer.id) # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.call(lead.reload) }
        .to have_enqueued_job(Ramon::NtfyPushJob).with(lead.id, title: 'Documentos: Tese Spec Entrada', body: include('sem WhatsApp'))
      expect(avisados).to eq([sdr.id])
      expect(historico.first).to include('sem WhatsApp')
    end

    it 'sem SDR avisa o closer; sem nenhum, os administradores', :aggregate_failures do
      lead.update_columns(sdr_id: nil, closer_id: closer.id) # rubocop:disable Rails/SkipsModelValidations
      described_class.call(lead.reload)
      expect(avisados).to eq([closer.id])

      Notification.delete_all
      lead.update_columns(closer_id: nil) # rubocop:disable Rails/SkipsModelValidations
      described_class.call(lead.reload)
      expect(avisados).to eq([admin.id])
    end
  end

  it 'conversa numa caixa sem IA: não mexe na conversa e avisa a equipe', :aggregate_failures do
    lead.update_columns(conversation_id: conversa.id, sdr_id: sdr.id) # rubocop:disable Rails/SkipsModelValidations

    described_class.call(lead.reload)

    expect(conversa.reload).to be_open
    expect(conversa.custom_attributes).to include('ia_pausa' => 'pausada')
    expect(avisados).to eq([sdr.id])
    expect(historico.first).to include('sem IA')
  end
end
