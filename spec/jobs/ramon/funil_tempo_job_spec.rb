require 'rails_helper'

RSpec.describe Ramon::FunilTempoJob do
  let(:account) { create(:account) }
  let(:negociacao) { account.lead_stages.find_by(label: 'fase-negociacao') }
  let(:ultima_chance) { account.lead_stages.find_by(label: 'fase-ultima-chance') }
  let(:qualificacao) { account.lead_stages.find_by(label: 'fase-qualificacao') }

  # `escreveu`: quando o cliente mandou a última mensagem (cria a conversa do lead antes de fixar o tempo na etapa).
  def lead_parado(etapa, dias, escreveu: nil)
    create(:lead, account: account, lead_stage: etapa).tap do |lead|
      if escreveu
        conversation = create(:conversation, account: account)
        create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: :incoming,
                         created_at: escreveu)
        lead.update_columns(conversation_id: conversation.id) # rubocop:disable Rails/SkipsModelValidations
      end
      lead.update_columns(stage_entered_at: dias.days.ago) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  before do
    Ramon::FunilAutomatico.mudar!(account, 'tempo_ultima_chance', 'on')
    Ramon::FunilAutomatico.mudar!(account, 'tempo_perdido', 'on')
  end

  it 'Negociação parada vai para Última chance' do
    lead = lead_parado(negociacao, negociacao.stalled_after_days + 1)
    described_class.perform_now
    expect(lead.reload.lead_stage).to eq(ultima_chance)
    desfazer = FunilAcao.find_by(lead: lead, peca: 'tempo_ultima_chance').desfazer
    expect(desfazer).to eq('etapa_id' => negociacao.id, 'etapa_produzida_id' => ultima_chance.id)
  end

  it 'Última chance parada vai para Perdido com o motivo do catálogo e desfazer' do
    lead = lead_parado(ultima_chance, ultima_chance.stalled_after_days + 1)
    described_class.perform_now
    lead.reload
    expect(lead.lead_stage).to be_is_lost
    expect(lead.lost_reason).to eq('Sumiu / não respondeu')
    desfazer = FunilAcao.find_by(lead: lead, peca: 'tempo_perdido').desfazer
    expect(desfazer).to eq('etapa_id' => ultima_chance.id, 'etapa_produzida_id' => lead.lead_stage_id)
  end

  it 'não anda duas etapas no mesmo dia' do
    lead = lead_parado(negociacao, negociacao.stalled_after_days + 30)
    described_class.perform_now
    expect(lead.reload.lead_stage).to eq(ultima_chance)
  end

  it 'lead dentro do prazo e lead em Qualificação não são tocados' do
    recente = lead_parado(negociacao, 1)
    qualif = lead_parado(qualificacao, 60)
    described_class.perform_now
    expect(recente.reload.lead_stage).to eq(negociacao)
    expect(qualif.reload.lead_stage).to eq(qualificacao)
  end

  it 'chaves off: nada acontece' do
    Ramon::FunilAutomatico.mudar!(account, 'tempo_ultima_chance', 'off')
    Ramon::FunilAutomatico.mudar!(account, 'tempo_perdido', 'off')
    negoc = lead_parado(negociacao, negociacao.stalled_after_days + 1)
    ultima = lead_parado(ultima_chance, ultima_chance.stalled_after_days + 1)
    described_class.perform_now
    expect(negoc.reload.lead_stage).to eq(negociacao)
    expect(ultima.reload.lead_stage).to eq(ultima_chance)
    expect(FunilAcao.count).to eq(0)
  end

  it 'cliente escreveu há 1 dia: nem Negociação nem Última chance andam (não sumiu)' do
    negoc = lead_parado(negociacao, negociacao.stalled_after_days + 1, escreveu: 1.day.ago)
    ultima = lead_parado(ultima_chance, ultima_chance.stalled_after_days + 1, escreveu: 1.day.ago)
    described_class.perform_now
    expect(negoc.reload.lead_stage).to eq(negociacao)
    expect(ultima.reload.lead_stage).to eq(ultima_chance)
    expect(FunilAcao.count).to eq(0)
  end

  it 'última mensagem do cliente mais velha que o prazo da etapa: anda' do
    negoc = lead_parado(negociacao, negociacao.stalled_after_days + 1, escreveu: (negociacao.stalled_after_days + 1).days.ago)
    ultima = lead_parado(ultima_chance, ultima_chance.stalled_after_days + 1, escreveu: (ultima_chance.stalled_after_days + 1).days.ago)
    described_class.perform_now
    expect(negoc.reload.lead_stage).to eq(ultima_chance)
    expect(ultima.reload.lead_stage).to be_is_lost
  end

  it 'um lead com erro não para os outros da conta nem a outra regra' do
    ruim = lead_parado(ultima_chance, ultima_chance.stalled_after_days + 1)
    bom = lead_parado(ultima_chance, ultima_chance.stalled_after_days + 1)
    negoc = lead_parado(negociacao, negociacao.stalled_after_days + 1)
    allow(Ramon::FunilAutomatico).to receive(:executar).and_wrap_original do |original, lead, **kwargs, &bloco|
      raise StandardError, 'boom' if lead.id == ruim.id

      original.call(lead, **kwargs, &bloco)
    end
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original

    expect { described_class.perform_now }.not_to raise_error

    expect(ruim.reload.lead_stage).to eq(ultima_chance)
    expect(bom.reload.lead_stage).to be_is_lost
    expect(negoc.reload.lead_stage).to eq(ultima_chance)
    expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(StandardError), account: account)
  end

  it 'conta sem a etapa Última chance: o job termina sem erro e a Negociação fica onde está' do
    lead = lead_parado(negociacao, negociacao.stalled_after_days + 1)
    ultima_chance.destroy!
    expect { described_class.perform_now }.not_to raise_error
    expect(lead.reload.lead_stage).to eq(negociacao)
  end
end
