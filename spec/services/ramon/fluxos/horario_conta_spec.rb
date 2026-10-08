require 'rails_helper'

RSpec.describe Ramon::Fluxos::HorarioConta do
  let(:account) { create(:account) }
  let(:push) { ['avisar_push', { 'texto' => 'oi' }] }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  # Fluxo que nasceu antes das datas do teste: o que nasce depois da hora de hoje só começa amanhã (T3).
  def fluxo_conta(gatilho, *passos)
    grafo = grafo_linear({ 'tipo' => 'horario_conta' }.merge(gatilho), *(passos.presence || [push]))
    fluxo_publicado(account, grafo).tap { |f| f.update_column(:created_at, sp('2026-10-01 00:00')) } # rubocop:disable Rails/SkipsModelValidations
  end

  def rodar(texto) = travel_to(sp(texto)) { described_class.disparar }

  def concluir(fluxo) = fluxo.execucoes.update_all(status: 'concluida') # rubocop:disable Rails/SkipsModelValidations

  it 'uma vez por dia a partir da hora, com a conta de alvo, e de novo no dia seguinte' do
    fluxo = fluxo_conta({ 'hora' => '08:00' })
    rodar('2026-10-06 07:59')
    expect(fluxo.execucoes.count).to eq(0)
    rodar('2026-10-06 08:00')
    rodar('2026-10-06 15:00')
    expect(fluxo.execucoes.pluck(:alvo_type, :alvo_id, :ensaio)).to eq([['Account', account.id, false]])
    concluir(fluxo)
    rodar('2026-10-07 08:01')
    expect(fluxo.execucoes.count).to eq(2)
  end

  it 'só nos dias marcados (0 = domingo)' do
    fluxo = fluxo_conta({ 'hora' => '08:00', 'dias' => [1, 2, 3, 4, 5] })
    rodar('2026-10-04 09:00') # domingo
    expect(fluxo.execucoes.count).to eq(0)
    rodar('2026-10-05 09:00') # segunda
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'a cada N minutos: 1 vez por bloco de N minutos' do
    fluxo = fluxo_conta({ 'a_cada_minutos' => 5 })
    %w[10:00:10 10:02:00 10:04:59 10:05:01 10:09:30].each do |hora|
      rodar("2026-10-06 #{hora}")
      concluir(fluxo)
    end
    expect(fluxo.execucoes.count).to eq(2)
  end

  it 'fluxo que nasce depois da hora começa amanhã (nunca repete a vez que o código já fez)' do
    grafo = grafo_linear({ 'tipo' => 'horario_conta', 'hora' => '08:00' }, push)
    fluxo = travel_to(sp('2026-10-06 10:00')) { fluxo_publicado(account, grafo) }
    rodar('2026-10-06 10:01')
    expect(fluxo.execucoes.count).to eq(0)
    rodar('2026-10-07 08:00')
    expect(fluxo.execucoes.count).to eq(1)
  end

  it 'roda sem lead: o push sai e a execução conclui' do
    fluxo = fluxo_conta({ 'hora' => '08:00' })
    rodar('2026-10-06 08:00')
    execucao = fluxo.execucoes.sole
    expect { Ramon::Fluxos::Executor.new(execucao).avancar! }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(execucao.reload.status).to eq('concluida')
    expect([execucao.lead, execucao.conversa]).to eq([nil, nil])
  end

  it 'erro num fluxo não derruba os outros' do
    quebrado = fluxo_conta({ 'hora' => '08:00' })
    bom = fluxo_conta({ 'hora' => '08:00' })
    allow(Ramon::Fluxos::Disparo).to receive(:new).and_call_original
    allow(Ramon::Fluxos::Disparo).to receive(:new).with(quebrado, account, {}, nil).and_raise(ActiveRecord::RecordInvalid)
    rodar('2026-10-06 08:00')
    expect([quebrado.execucoes.count, bom.execucoes.count]).to eq([0, 1])
  end

  describe 'rotina da conta migrada: quem pega a vez faz, nunca os dois' do
    let(:resumo) do
      Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia').sole
                             .tap { |f| f.update_column(:created_at, sp('2026-10-01 00:00')) } # rubocop:disable Rails/SkipsModelValidations
    end

    def cron(texto, nome = 'resumo_do_dia')
      [].tap { |l| travel_to(sp(texto)) { Ramon::Fluxos::Rotinas::Conta.cada_conta(nome) { |a| l << a.id } } }
    end

    it 'no comando: o fluxo faz (de verdade, com assumido), chamando o mesmo job só para a conta; o cron pula' do
      resumo
      allow(Ramon::DailyDigestJob).to receive(:perform_now)
      with_modified_env(RAMON_FLUXO_ROTINAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'resumo_do_dia', 'normal')
        expect { rodar('2026-10-06 08:00') }.not_to have_enqueued_job(Ramon::DailyDigestJob)
        expect(cron('2026-10-06 08:00:30')).to eq([])
      end
      execucao = resumo.execucoes.sole
      expect([execucao.ensaio, execucao.contexto.dig('gatilho', 'assumido')]).to eq([false, true])
      Ramon::Fluxos::Executor.new(execucao).avancar!
      expect(Ramon::DailyDigestJob).to have_received(:perform_now).with(account.id)
      expect(execucao.reload.trilha.last['resumo']).to eq('fez: o resumo do dia')
    end

    it 'fora do comando (sombra): nenhuma execução; o relógio faz pelo código e o cron do mesmo dia não repete' do
      resumo
      expect { rodar('2026-10-06 08:00') }.to have_enqueued_job(Ramon::DailyDigestJob).with(account.id)
      expect(resumo.execucoes.count).to eq(0)
      expect(cron('2026-10-06 08:00:40')).to eq([])
    end

    it 'virar a chave depois da hora não roda a vez de novo (o cron já pegou)' do
      resumo
      expect(cron('2026-10-06 08:00')).to eq([account.id])
      with_modified_env(RAMON_FLUXO_ROTINAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'resumo_do_dia', 'normal')
        expect { rodar('2026-10-06 10:00') }.not_to have_enqueued_job(Ramon::DailyDigestJob)
      end
      expect(resumo.execucoes.count).to eq(0)
    end

    it 'fluxo criado depois da hora (o cron já fez sem ele): ninguém repete hoje; amanhã, 1 vez só' do
      account # existe antes do cron (o let é preguiçoso)
      expect(cron('2026-10-06 08:00')).to eq([account.id])
      fluxo = travel_to(sp('2026-10-06 10:00')) { Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia').sole }
      expect { rodar('2026-10-06 10:01') }.not_to have_enqueued_job(Ramon::DailyDigestJob)
      expect(cron('2026-10-06 10:01:30')).to eq([])
      expect { rodar('2026-10-07 08:00') }.to have_enqueued_job(Ramon::DailyDigestJob).with(account.id)
      expect(cron('2026-10-07 08:00:30')).to eq([])
      expect(fluxo.execucoes.count).to eq(0)
    end

    it 'no comando mas ocupado (a execução de ontem ainda viva): o código faz a vez de hoje (reserva)' do
      resumo.execucoes.create!(account: account, alvo: account, status: 'esperando', retomar_em: 1.hour.from_now)
      with_modified_env(RAMON_FLUXO_ROTINAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'resumo_do_dia', 'normal')
        expect { rodar('2026-10-06 08:00') }.to have_enqueued_job(Ramon::DailyDigestJob).with(account.id)
      end
      expect(resumo.execucoes.count).to eq(1)
    end

    it 'erro do motor ao criar a execução: o código faz (reserva)' do
      resumo
      allow(Ramon::Fluxos::Disparo).to receive(:new).and_raise(StandardError, 'motor')
      with_modified_env(RAMON_FLUXO_ROTINAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'resumo_do_dia', 'normal')
        expect { rodar('2026-10-06 08:00') }.to have_enqueued_job(Ramon::DailyDigestJob).with(account.id)
      end
    end

    it 'publicar peças: sem peça vencida o fluxo nem começa (nem gasta a vez); com peça, o fluxo faz' do
      publicar = Ramon::Fluxos::Migracao.semear(account, 'publicar_pecas').sole
      with_modified_env(RAMON_FLUXO_PUBLICAR_PECAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'publicar_pecas', 'normal')
        rodar('2026-10-06 12:00')
        expect([publicar.execucoes.count, publicar.reload.ultimo_disparo_em]).to eq([0, nil])
        create(:peca, account: account, status: 'agendado', agendado_para: sp('2026-10-06 11:59'), imagens: ['u1'])
        rodar('2026-10-06 12:01')
      end
      expect(publicar.execucoes.sole.ensaio).to be(false)
    end

    it 'publicar peças em sombra: 1 vez por minuto — quem pega o minuto (relógio ou cron) faz, o outro pula' do
      publicar = Ramon::Fluxos::Migracao.semear(account, 'publicar_pecas').sole
      create(:peca, account: account, status: 'agendado', agendado_para: sp('2026-10-06 11:59'), imagens: ['u1'])
      expect { rodar('2026-10-06 12:00') }.to have_enqueued_job(Ramon::PublicarPecasJob).with(account.id)
      expect(cron('2026-10-06 12:00:30', 'publicar_pecas')).to eq([])
      expect(cron('2026-10-06 12:01:00', 'publicar_pecas')).to eq([account.id])
      expect { rodar('2026-10-06 12:01:20') }.not_to have_enqueued_job(Ramon::PublicarPecasJob)
      expect(publicar.execucoes.count).to eq(0)
    end
  end
end
