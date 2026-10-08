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

  it 'as 7 rotinas da conta: no registro, cada uma com a sua migração (3 chaves por família)' do
    expect(todas.map { |nome| Ramon::Fluxos::Rotinas.alvo(nome) }.uniq).to eq(['conta'])
    envs = Ramon::Fluxos::Migracao::GRUPOS.slice(*todas).transform_values { |g| g[:env] }
    expect(envs).to eq('resumo_do_dia' => 'RAMON_FLUXO_ROTINAS', 'retrato_funil' => 'RAMON_FLUXO_ROTINAS',
                       'fechamento_extrato' => 'RAMON_FLUXO_ROTINAS', 'espelho_painel' => 'RAMON_FLUXO_ROTINAS',
                       'copiloto_noturno' => 'RAMON_FLUXO_ROTINAS', 'publicar_pecas' => 'RAMON_FLUXO_PUBLICAR_PECAS',
                       'avisos_painel' => 'RAMON_FLUXO_AVISOS_PAINEL')
    expect(Ramon::Fluxos::Migracao.gatilhos('publicar_pecas')).to eq('publicar_pecas' => 'horario_conta')
  end

  it 'criar: os 7 nascem em sombra, ligados, publicados, no horário de hoje do código' do
    horarios = todas.to_h do |nome|
      novo = Ramon::Fluxos::Migracao.semear(account, nome).sole
      [nome, Ramon::Fluxos::Grafo.new(novo.versao_publicada.grafo).gatilho['config'].slice('hora', 'a_cada_minutos')]
    end
    expect(horarios).to eq('resumo_do_dia' => { 'hora' => '08:00' }, 'retrato_funil' => { 'hora' => '00:05' },
                           'fechamento_extrato' => { 'hora' => '00:20' }, 'espelho_painel' => { 'hora' => '00:30' },
                           'copiloto_noturno' => { 'hora' => '05:00' }, 'publicar_pecas' => { 'a_cada_minutos' => 1 },
                           'avisos_painel' => { 'hora' => '08:00' })
    expect(account.fluxos.where(sistema_chave: todas, origem: 'usuario').pluck(:modo, :ativo, :gatilho_tipo, :limite_dia).uniq)
      .to eq([['sombra', true, 'horario_conta', nil]])
  end

  it 'rodar: "agora" roda o job de hoje só para esta conta; o ensaio só descreve' do
    allow(Ramon::DailyDigestJob).to receive(:perform_now)
    expect(described_class.rodar('resumo_do_dia', ctx(ensaio: true))).to eq('faria: o resumo do dia')
    expect(Ramon::DailyDigestJob).not_to have_received(:perform_now)
    expect(described_class.rodar('resumo_do_dia', ctx)).to eq('fez: o resumo do dia')
    expect(Ramon::DailyDigestJob).to have_received(:perform_now).with(account.id)
  end

  it 'rodar: "fila" enfileira o job da conta (passaria de 10 min dentro do passo)' do
    expect(described_class.rodar('espelho_painel', ctx(ensaio: true))).to eq('faria: o espelho do Painel do Cliente (na fila)')
    expect { expect(described_class.rodar('publicar_pecas', ctx)).to eq('pôs na fila: a publicação das peças no Instagram') }
      .to have_enqueued_job(Ramon::PublicarPecasJob).with(account.id)
  end

  it 'avisos do Painel: com PORTAL_AVISOS desligado nada é chamado e a trilha diz por quê' do
    allow(Ramon::PortalAvisosJob).to receive(:perform_now)
    expect(described_class.rodar('avisos_painel', ctx)).to eq('avisos do Painel desligados até aprovar os textos (PORTAL_AVISOS) — nada enviado')
    expect(Ramon::PortalAvisosJob).not_to have_received(:perform_now)
    with_modified_env(PORTAL_AVISOS: 'on') { expect(described_class.rodar('avisos_painel', ctx)).to eq('fez: os avisos do Painel do Cliente') }
    expect(Ramon::PortalAvisosJob).to have_received(:perform_now).with(account.id)
  end

  it 'rotina da conta num fluxo de lead não publica' do
    grafo = Ramon::Fluxos::Grafo.new(grafo_linear({ 'tipo' => 'manual' }, ['rotina', { 'rotina' => 'resumo_do_dia' }]))
    expect(grafo.erros).to eq(['Passo p1: esta rotina é da conta toda — só roda no gatilho Horário da conta'])
  end

  describe 'cada_conta (o job do código)' do
    # let! na ordem: account nasce antes (find_each vai por id)
    let!(:account) { create(:account) }
    let!(:outra) { create(:account) }

    def contas(account_id = nil) = [].tap { |lista| described_class.cada_conta('resumo_do_dia', account_id) { |a| lista << a.id } }

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
