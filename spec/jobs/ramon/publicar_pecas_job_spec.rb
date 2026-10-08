require 'rails_helper'

RSpec.describe Ramon::PublicarPecasJob do
  let(:peca) { create(:peca, status: 'agendado', agendado_para: 1.minute.ago, imagens: ['u1']) }
  let(:publisher) { instance_double(Ramon::InstagramPublisher, publicar: 'm9', permalink: 'https://ig/p/x') }

  before { allow(Ramon::InstagramPublisher).to receive(:new).and_return(publisher) }

  it 'publica a peça vencida e grava id e link' do
    peca
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::ConteudoDriveJob).with(peca.id)
    expect(peca.reload).to have_attributes(status: 'publicado', ig_media_id: 'm9', permalink: 'https://ig/p/x', erro: nil)
  end

  it 'fluxos do acervo no comando: o Drive sai pelo fluxo; a rajada de status (publicando → publicado) não perde o Notion' do
    peca
    account = peca.account
    with_modified_env(RAMON_FLUXO_ACERVO_PECAS: 'on') do
      Ramon::Fluxos::Migracao.semear(account, 'acervo_pecas')
      Ramon::Fluxos::Migracao.mudar_modo!(account, 'acervo_pecas', 'normal')
      # 'publicando' cria a execução do espelho (ainda na fila); 'publicado' bate no índice único → o código espelha (reserva)
      expect { described_class.perform_now }
        .to have_enqueued_job(Ramon::NotionEspelhoJob).with(peca.id).exactly(:once)
    end
    expect(Ramon::Fluxos::Migracao.fluxo(account, 'acervo_pecas_notion').execucoes.count).to eq(1)
    expect { perform_enqueued_jobs(only: Ramon::FluxoAvancarJob) }
      .to have_enqueued_job(Ramon::ConteudoDriveJob).with(peca.id).and have_enqueued_job(Ramon::NotionEspelhoJob).with(peca.id)
    expect(peca.reload.status).to eq('publicado')
  end

  it 'não mexe em peça agendada pro futuro' do
    peca.update_columns(agendado_para: 1.hour.from_now) # rubocop:disable Rails/SkipsModelValidations
    described_class.perform_now
    expect(publisher).not_to have_received(:publicar)
  end

  it 'erro da Meta vira falhou e avisa no celular' do
    allow(publisher).to receive(:publicar).and_raise(Ramon::InstagramPublisher::Erro, 'Invalid image')
    peca
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(peca.reload).to have_attributes(status: 'falhou', erro: 'Invalid image')
  end

  it 'nunca republica peça que já tem ig_media_id' do
    peca.update_columns(ig_media_id: 'm1') # rubocop:disable Rails/SkipsModelValidations
    described_class.perform_now
    expect(publisher).not_to have_received(:publicar)
    expect(peca.reload.status).to eq 'publicado'
  end

  it 'permalink falhando não derruba: fica publicado com o id' do
    allow(publisher).to receive(:permalink).and_return(nil)
    peca
    described_class.perform_now
    expect(peca.reload).to have_attributes(status: 'publicado', ig_media_id: 'm9', permalink: nil)
  end

  it 'publicando há mais de 30 min vira falhou com aviso de conferir' do
    travada = create(:peca, status: 'publicando', publicacao_iniciada_em: 31.minutes.ago)
    expect { described_class.perform_now }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(travada.reload).to have_attributes(status: 'falhou')
    expect(travada.erro).to include('conferir no Instagram')
  end

  it 'permalink levantando depois do publish: fica publicado com o id' do
    allow(publisher).to receive(:permalink).and_raise(StandardError, 'boom')
    peca
    described_class.perform_now
    expect(peca.reload).to have_attributes(status: 'publicado', ig_media_id: 'm9', erro: nil)
  end

  it 'publicando há mais de 30 min COM ig_media_id vira publicado' do
    no_ar = create(:peca, status: 'publicando', publicacao_iniciada_em: 31.minutes.ago, ig_media_id: 'm5')
    described_class.perform_now
    expect(no_ar.reload).to have_attributes(status: 'publicado', ig_media_id: 'm5')
  end

  it 'publicando há 20 min é deixada em paz' do
    andando = create(:peca, status: 'publicando', publicacao_iniciada_em: 20.minutes.ago)
    described_class.perform_now
    expect(andando.reload.status).to eq 'publicando'
  end

  it 'B5: pendente? só com peça vencida ou presa; fluxo no comando tira a conta do cron; com o id, só ela' do
    peca
    expect(described_class.pendente?(peca.account)).to be(true)
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).and_call_original
    allow(Ramon::Fluxos::Migracao).to receive(:assumiu?).with(peca.account, 'publicar_pecas').and_return(true)
    described_class.perform_now
    expect(publisher).not_to have_received(:publicar)
    described_class.perform_now(peca.account_id)
    expect(peca.reload.status).to eq('publicado')
    expect(described_class.pendente?(peca.account)).to be(false)
  end
end
