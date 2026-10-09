require 'rails_helper'

RSpec.describe Ramon::Fluxos::Rotinas::Conta do
  let(:account) { create(:account) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'horario_conta', 'hora' => '08:00' })) }
  let(:todas) { described_class::JOBS.keys }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  # status concluida: fora do índice único (várias por exemplo)
  def ctx(ensaio: false)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: account, ensaio: ensaio, status: 'concluida'))
  end

  it 'só o resumo do dia segue como rotina da conta no fluxo (as outras 6 são regra fixa, 08/10)' do
    expect(todas).to eq(['resumo_do_dia'])
    expect(Ramon::Fluxos::Rotinas.alvo('resumo_do_dia')).to eq('conta')
    expect(Ramon::Fluxos::Migracao.grupo('resumo_do_dia')).to include(env: 'RAMON_FLUXO_ROTINAS', fluxos: { 'resumo_do_dia' => 'horario_conta' })
    expect(Ramon::Fluxos::Rotinas.alvo('publicar_pecas')).to be_nil
  end

  it 'criar: nasce em sombra, ligado, publicado, às 08:00 (o horário do código)' do
    novo = Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia').sole
    expect(Ramon::Fluxos::Grafo.new(novo.versao_publicada.grafo).gatilho['config'].slice('hora', 'a_cada_minutos')).to eq('hora' => '08:00')
    expect([novo.modo, novo.ativo, novo.gatilho_tipo, novo.limite_dia]).to eq(['sombra', true, 'horario_conta', nil])
  end

  it 'rodar: roda o job de hoje só para esta conta; o ensaio só descreve' do
    allow(Ramon::DailyDigestJob).to receive(:perform_now)
    expect(described_class.rodar('resumo_do_dia', ctx(ensaio: true))).to eq('faria: o resumo do dia')
    expect(Ramon::DailyDigestJob).not_to have_received(:perform_now)
    expect(described_class.rodar('resumo_do_dia', ctx)).to eq('fez: o resumo do dia')
    expect(Ramon::DailyDigestJob).to have_received(:perform_now).with(account.id)
  end

  it 'rotina da conta num fluxo de lead não publica' do
    grafo = Ramon::Fluxos::Grafo.new(grafo_linear({ 'tipo' => 'manual' }, ['rotina', { 'rotina' => 'resumo_do_dia' }]))
    expect(grafo.erros).to eq(['Passo p1: esta rotina é da conta toda — só roda no gatilho Horário da conta'])
  end

  describe 'cada_conta (o job do código)' do
    # let! na ordem: account nasce antes (find_each vai por id)
    let!(:account) { create(:account) }
    let!(:outra) { create(:account) }

    def contas(account_id = nil, nome = 'resumo_do_dia') = [].tap { |lista| described_class.cada_conta(nome, account_id) { |a| lista << a.id } }

    it 'sem o fluxo: todas as contas, como sempre; com o id: só aquela' do
      expect(contas).to eq([account.id, outra.id])
      expect(contas(outra.id)).to eq([outra.id])
    end

    it 'fluxo no comando: a conta fica de fora' do
      Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia')
      with_modified_env(RAMON_FLUXO_ROTINAS: 'on') do
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'resumo_do_dia', 'normal')
        expect(contas).to eq([outra.id])
      end
    end

    it 'fluxo criado mas fora do comando: o código faz se pegar a vez — 1 vez no dia' do
      novo = Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia').sole
      novo.update_column(:created_at, sp('2026-10-01 00:00')) # rubocop:disable Rails/SkipsModelValidations
      travel_to(sp('2026-10-06 08:00')) { expect(contas).to eq([account.id, outra.id]) }
      travel_to(sp('2026-10-06 08:00:40')) { expect(contas).to eq([outra.id]) } # a vez de hoje já foi
    end

    it 'diária num fluxo editado para "a cada N min", fora do comando: o relógio não faz pelo código, o cron faz como sempre' do
      novo = Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia').sole
      allow(Ramon::Fluxos::HorarioConta).to receive(:config).and_return('a_cada_minutos' => 5)
      expect(Ramon::Fluxos::HorarioConta.reivindicar(novo, sp('2026-10-06 08:00'))).to be(true) # o relógio pegou a vez do bloco
      expect { described_class.decidir(novo) }.not_to have_enqueued_job(Ramon::DailyDigestJob)
      travel_to(sp('2026-10-06 08:00:40')) { expect(contas).to eq([account.id, outra.id]) }
    end
  end
end
