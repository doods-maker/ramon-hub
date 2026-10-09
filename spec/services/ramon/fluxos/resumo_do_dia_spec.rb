require 'rails_helper'

RSpec.describe Ramon::Fluxos::ResumoDoDia do
  let(:account) { create(:account) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'horario_conta', 'hora' => '08:00' })) }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  # status concluida: fora do índice único (várias por exemplo)
  def ctx(ensaio: false, alvo: account)
    Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio, status: 'concluida'))
  end

  def rodar(contexto) = Ramon::Fluxos::Passos::Rotina.rotina({ 'rotina' => 'resumo_do_dia' }, contexto)

  it 'só o resumo do dia segue como rotina da conta no fluxo (as outras 6 são regra fixa, 08/10)' do
    expect(Ramon::Fluxos::Passos::Rotina::ROTINAS.select { |_nome, alvo| alvo == 'conta' }.keys).to eq(['resumo_do_dia'])
    expect(Ramon::Fluxos::Migracao.grupo('resumo_do_dia')).to include(env: 'RAMON_FLUXO_RESUMO_DIA', fluxos: { 'resumo_do_dia' => 'horario_conta' })
    expect(Ramon::Fluxos::Passos::Rotina::ROTINAS['publicar_pecas']).to be_nil
  end

  it 'a chave é RAMON_FLUXO_RESUMO_DIA; o nome antigo (RAMON_FLUXO_ROTINAS) vale só enquanto o novo não existe' do
    ligada = -> { Ramon::Fluxos::Migracao.ligada?('resumo_do_dia') }
    expect(ligada.call).to be(false)
    with_modified_env(RAMON_FLUXO_RESUMO_DIA: 'on') { expect(ligada.call).to be(true) }
    with_modified_env(RAMON_FLUXO_ROTINAS: 'on') { expect(ligada.call).to be(true) }
    with_modified_env(RAMON_FLUXO_RESUMO_DIA: 'off', RAMON_FLUXO_ROTINAS: 'on') { expect(ligada.call).to be(false) }
    with_modified_env(RAMON_FLUXO_ROTINAS: 'on') { expect(Ramon::Fluxos::Migracao.ligada?('chegada_cliente')).to be(false) }
  end

  it 'criar: nasce em sombra, ligado, publicado, às 08:00 (o horário do código)' do
    novo = Ramon::Fluxos::Migracao.semear(account, 'resumo_do_dia').sole
    expect(Ramon::Fluxos::Grafo.new(novo.versao_publicada.grafo).gatilho['config'].slice('hora', 'a_cada_minutos')).to eq('hora' => '08:00')
    expect([novo.modo, novo.ativo, novo.gatilho_tipo, novo.limite_dia]).to eq(['sombra', true, 'horario_conta', nil])
  end

  it 'a rotina pronta (passo Rotina): roda o job de hoje só para esta conta; o ensaio só descreve' do
    allow(Ramon::DailyDigestJob).to receive(:perform_now)
    expect(rodar(ctx(ensaio: true))).to eq(saida: 's', resumo: 'faria: o resumo do dia')
    expect(Ramon::DailyDigestJob).not_to have_received(:perform_now)
    expect(rodar(ctx)).to eq(saida: 's', resumo: 'fez: o resumo do dia')
    expect(Ramon::DailyDigestJob).to have_received(:perform_now).with(account.id)
  end

  it 'a rotina da conta com um lead de alvo é passo impossível (falha na hora)' do
    expect { rodar(ctx(alvo: create(:lead, account: account))) }
      .to raise_error(Ramon::Fluxos::PassoImpossivel, 'esta rotina é da conta toda (gatilho Horário da conta)')
  end

  it 'rotina da conta num fluxo de lead não publica' do
    grafo = Ramon::Fluxos::Grafo.new(grafo_linear({ 'tipo' => 'manual' }, ['rotina', { 'rotina' => 'resumo_do_dia' }]))
    expect(grafo.erros).to eq(['Passo p1: esta rotina é da conta toda — só roda no gatilho Horário da conta'])
  end

  describe 'cada_conta (o job do código)' do
    # let! na ordem: account nasce antes (find_each vai por id)
    let!(:account) { create(:account) }
    let!(:outra) { create(:account) }

    def contas(account_id = nil) = [].tap { |lista| described_class.cada_conta(account_id) { |a| lista << a.id } }

    it 'sem o fluxo: todas as contas, como sempre; com o id: só aquela' do
      expect(contas).to eq([account.id, outra.id])
      expect(contas(outra.id)).to eq([outra.id])
    end

    it 'fluxo no comando (com o nome antigo da chave, como a VPS antes da troca): a conta fica de fora' do
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
