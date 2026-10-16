# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ramon::FunilObservadorJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversation, lead_stage: account.lead_stages.find_by(label: 'fase-novo')) }
  let(:observador) { instance_double(Ramon::FunilObservador, perform: nil) }

  def mensagem(tipo = :incoming, **attrs)
    create(:message, account: account, conversation: conversation, inbox: conversation.inbox, message_type: tipo, **attrs)
  end

  before do
    lead
    allow(Ramon::FunilObservador).to receive(:new).with(lead).and_return(observador)
    Ramon::FunilAutomatico.mudar!(account, 'etapa_ia', 'ensaio')
  end

  it 'caso normal: roda o observador uma vez' do
    msg = mensagem
    described_class.perform_now(msg.id)
    expect(observador).to have_received(:perform).once
  end

  it 'mensagem superada por outra pública (incoming ou outgoing): não roda' do
    msg = mensagem
    mensagem(:outgoing)
    described_class.perform_now(msg.id)
    expect(observador).not_to have_received(:perform)
  end

  it 'nota privada posterior não supera a mensagem' do
    msg = mensagem
    mensagem(:outgoing, private: true)
    described_class.perform_now(msg.id)
    expect(observador).to have_received(:perform).once
  end

  it 'todas as peças off: não roda' do
    msg = mensagem
    Ramon::FunilAutomatico.mudar!(account, 'etapa_ia', 'off')
    described_class.perform_now(msg.id)
    expect(observador).not_to have_received(:perform)
  end

  it 'só temperatura em ensaio: não roda' do
    msg = mensagem
    Ramon::FunilAutomatico.mudar!(account, 'etapa_ia', 'off')
    Ramon::FunilAutomatico.mudar!(account, 'temperatura', 'ensaio')
    described_class.perform_now(msg.id)
    expect(observador).not_to have_received(:perform)
  end

  it 'reuniao_ia sozinha (inclusive em ensaio): roda' do
    msg = mensagem
    Ramon::FunilAutomatico.mudar!(account, 'etapa_ia', 'off')
    Ramon::FunilAutomatico.mudar!(account, 'reuniao_ia', 'ensaio')
    described_class.perform_now(msg.id)
    expect(observador).to have_received(:perform).once
  end

  it 'temperatura on sozinha: roda' do
    msg = mensagem
    Ramon::FunilAutomatico.mudar!(account, 'etapa_ia', 'off')
    Ramon::FunilAutomatico.mudar!(account, 'temperatura', 'on')
    described_class.perform_now(msg.id)
    expect(observador).to have_received(:perform).once
  end

  it 'só colheita em ensaio: não roda; on: roda' do
    msg = mensagem
    Ramon::FunilAutomatico.mudar!(account, 'etapa_ia', 'off')
    Ramon::FunilAutomatico.mudar!(account, 'colheita', 'ensaio')
    described_class.perform_now(msg.id)
    expect(observador).not_to have_received(:perform)
    Ramon::FunilAutomatico.mudar!(account, 'colheita', 'on')
    described_class.perform_now(msg.id)
    expect(observador).to have_received(:perform).once
  end

  it 'promessas sozinha (inclusive em ensaio): roda' do
    msg = mensagem
    Ramon::FunilAutomatico.mudar!(account, 'etapa_ia', 'off')
    Ramon::FunilAutomatico.mudar!(account, 'promessas', 'ensaio')
    described_class.perform_now(msg.id)
    expect(observador).to have_received(:perform).once
  end

  it 'só pendencias em ensaio: não roda; on: roda' do
    msg = mensagem
    Ramon::FunilAutomatico.mudar!(account, 'etapa_ia', 'off')
    Ramon::FunilAutomatico.mudar!(account, 'pendencias', 'ensaio')
    described_class.perform_now(msg.id)
    expect(observador).not_to have_received(:perform)
    Ramon::FunilAutomatico.mudar!(account, 'pendencias', 'on')
    described_class.perform_now(msg.id)
    expect(observador).to have_received(:perform).once
  end

  it 'esgotadas as 3 tentativas do erro transitório: rastreia e descarta, sem re-lançar' do
    msg = mensagem
    allow(observador).to receive(:perform).and_raise(Ramon::LlmClient::TransientError, 'timeout')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    expect { perform_enqueued_jobs { described_class.perform_later(msg.id) } }.not_to raise_error
    expect(observador).to have_received(:perform).exactly(3).times
    expect(tracker).to have_received(:capture_exception).once
  end

  it 'lead perdido: não roda' do
    msg = mensagem
    lead.update_columns(lost_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    described_class.perform_now(msg.id)
    expect(observador).not_to have_received(:perform)
  end

  it 'erro não transitório é capturado, sem re-lançar' do
    msg = mensagem
    allow(observador).to receive(:perform).and_raise(StandardError, 'boom')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    expect { described_class.perform_now(msg.id) }.not_to raise_error
    expect(tracker).to have_received(:capture_exception)
  end

  it 'erro transitório do LLM não é engolido: agenda nova tentativa' do
    msg = mensagem
    allow(observador).to receive(:perform).and_raise(Ramon::LlmClient::TransientError, 'timeout')
    expect { described_class.perform_now(msg.id) }.to have_enqueued_job(described_class).with(msg.id)
  end

  it 'mensagem apagada: sai sem erro' do
    msg = mensagem
    msg.destroy!
    expect { described_class.perform_now(msg.id) }.not_to raise_error
    expect(observador).not_to have_received(:perform)
  end
end
