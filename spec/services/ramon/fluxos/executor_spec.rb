require 'rails_helper'

RSpec.describe Ramon::Fluxos::Executor do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }
  let(:lead) { create(:lead, account: account, conversation: conversa, contact: conversa.contact) }

  def iniciar(grafo, alvo: lead, **attrs)
    fluxo = fluxo_publicado(account, grafo)
    g = fluxo.versao_publicada.grafo
    fluxo.execucoes.create!({ account: account, versao: fluxo.versao_publicada, alvo: alvo,
                              status: 'esperando', retomar_em: Time.current,
                              no_atual: Ramon::Fluxos::Grafo.new(g).proximo('g', 's'),
                              contexto: { 'etapa_inicial_id' => lead.lead_stage_id } }.merge(attrs))
  end

  def avancar(execucao) = described_class.new(execucao).avancar!.then { execucao.reload }

  it 'todo tipo de passo do desenho tem quem execute' do
    expect(described_class::PASSOS.keys).to match_array(Ramon::Fluxos::Grafo::TIPOS_PASSO)
  end

  it 'anda até o fim, grava trilha e balão na conversa' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'a' }],
                             ['criar_tarefa', { 'titulo' => 'T' }]))
    expect { avancar(e) }.to have_enqueued_job(Conversations::ActivityMessageJob)
    expect(e.status).to eq('concluida')
    expect(e.trilha.pluck('no')).to eq(%w[p1 p2])
  end

  it 'para na espera e retoma só quando vence (relógio duplicado não anda 2x)' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 2, 'unidade' => 'dias' }],
                             ['nota_privada', { 'texto' => 'depois' }]))
    avancar(e)
    expect(e.status).to eq('esperando')
    expect(e.no_atual).to eq('p2')

    avancar(e) # chamado antes da hora: não anda
    expect(e.status).to eq('esperando')

    travel 2.days + 1.minute do
      avancar(e)
      expect(e.status).to eq('concluida')
      avancar(e) # segundo job do relógio: nada muda
      expect(e.trilha.count { |t| t['no'] == 'p2' }).to eq(1)
    end
  end

  it 'cancela se o lead saiu da etapa durante a espera' do
    e = iniciar(grafo_linear({ 'tipo' => 'lead_criado' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'x' }]))
    avancar(e)
    lead.update!(lead_stage: create(:lead_stage, account: account, position: 9))
    travel(2.hours) { expect(avancar(e).status).to eq('cancelada') }
  end

  it 'fluxo desligado durante a espera → cancelada' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'x' }]))
    avancar(e)
    e.fluxo.update!(ativo: false)
    travel(2.hours) { expect(avancar(e).status).to eq('cancelada') }
    expect(e.trilha.last['resumo']).to eq('cancelado: o fluxo foi desligado')
    expect(conversa.messages.where(private: true, content: 'x')).to be_empty
  end

  it 'sombra: desligar o fluxo cancela quem espera (é assim que se para a sombra)' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'x' }]), ensaio: true)
    avancar(e)
    e.fluxo.update!(ativo: false)
    travel(2.hours) { expect(avancar(e).status).to eq('cancelada') }
  end

  it '"Testar com um lead…" roda mesmo com o fluxo desligado' do
    fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'x' }]), ativo: false)
    expect(Ramon::Fluxos::Disparo.ensaiar(fluxo, lead, usar: 'publicada').status).to eq('concluida')
  end

  it 'a reunião (tarefa) apagada durante a espera cancela o ciclo dela' do
    tarefa = create(:lead_task, account: account, lead: lead, kind: 'meeting', title: 'R', due_at: 2.days.from_now)
    e = iniciar(grafo_linear({ 'tipo' => 'reuniao_na_agenda' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'x' }]), alvo: tarefa)
    avancar(e)
    tarefa.destroy!
    travel(2.hours) { expect(avancar(e).status).to eq('cancelada') }
    expect(e.trilha.last['resumo']).to eq('cancelado: o alvo foi apagado (lead, conversa ou reunião)')
  end

  it 'versão congelada: publicar de novo não muda execução em andamento' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'v1' }]))
    avancar(e)
    e.fluxo.update!(rascunho: grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                                           ['nota_privada', { 'texto' => 'v2' }]))
    e.fluxo.publicar!(nil)
    travel(2.hours) { avancar(e) }
    expect(conversa.messages.where(private: true).last.content).to eq('v1')
  end

  it 'erro: tenta em 1, 5, 15 min e depois falha avisando' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'x' }]))
    allow(Ramon::Fluxos::Passos::Conversa).to receive(:nota_privada).and_raise(StandardError, 'fora do ar')
    [1, 5, 15].each do |min|
      avancar(e)
      expect(e.status).to eq('esperando')
      expect(e.retomar_em).to be_within(5.seconds).of(min.minutes.from_now)
      e.update!(retomar_em: 1.second.ago)
    end
    expect { avancar(e) }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(e.status).to eq('falhou')
    expect(e.erro).to include('fora do ar')
  end

  it 'passo impossível falha na hora' do
    sem_lead = create(:conversation, account: account)
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['mover_etapa', { 'etapa_id' => lead.lead_stage_id }]), alvo: sem_lead)
    expect(avancar(e).status).to eq('falhou')
    expect(e.tentativas).to eq(0)
  end

  it 'alvo apagado durante a espera → cancelada' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }],
                             ['nota_privada', { 'texto' => 'x' }]))
    avancar(e)
    FluxoExecucao.where(id: e.id).update_all(alvo_id: 0) # rubocop:disable Rails/SkipsModelValidations
    travel(2.hours) { expect(avancar(e).status).to eq('cancelada') }
  end

  it 'escolha segue a saída do caso' do
    casos = [{ 'chave' => 'c1', 'rotulo' => 'Indicação', 'valores' => ['indicacao'] },
             { 'chave' => 'c2', 'rotulo' => 'Anúncio', 'valores' => ['anuncio'] }]
    d = grafo_linear({ 'tipo' => 'manual' })
    d['nos'] += [no_fluxo('x', 'escolha', { 'campo' => 'origem', 'casos' => casos }),
                 no_fluxo('a', 'nota_privada', { 'texto' => 'A' }), no_fluxo('b', 'nota_privada', { 'texto' => 'B' })]
    d['setas'] += [{ 'de' => 'g', 'saida' => 's', 'para' => 'x' }, { 'de' => 'x', 'saida' => 'c1', 'para' => 'a' },
                   { 'de' => 'x', 'saida' => 'outro', 'para' => 'b' }]
    lead.update!(source: 'indicacao')
    e = iniciar(d)
    expect(avancar(e).trilha.pluck('no')).to eq(%w[x a])
  end

  it 'ensaio pula espera e não executa ações' do
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'quantidade' => 3, 'unidade' => 'dias' }],
                             ['nota_privada', { 'texto' => 'x' }]),
                ensaio: true, contexto: { 'pular_esperas' => true })
    expect { avancar(e) }.not_to(change { conversa.messages.count })
    expect(e.status).to eq('concluida')
    expect(e.trilha.last['resumo']).to start_with('faria: ')
  end

  it 'eventos disparados pelo passo levam o executor como autor (performed_by)' do
    nova = create(:lead_stage, account: account, position: 9)
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['mover_etapa', { 'etapa_id' => nova.id }]))
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    avancar(e)
    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::LEAD_UPDATED, anything,
            hash_including(changed_attributes: { 'lead_stage_id' => [anything, nova.id] }, performed_by: e))
  end

  it 'mover_etapa → esperar → não se cancela sozinho' do
    nova = create(:lead_stage, account: account, position: 9)
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['mover_etapa', { 'etapa_id' => nova.id }],
                             ['esperar', { 'quantidade' => 1, 'unidade' => 'horas' }], ['nota_privada', { 'texto' => 'x' }]))
    avancar(e)
    expect(e.status).to eq('esperando')
    travel(2.hours) { expect(avancar(e).status).to eq('concluida') }
  end

  it 'grava a execução a cada passo (passo lento não parece órfão ao relógio)' do
    vistos = []
    allow(Ramon::Fluxos::Passos::Lead).to receive(:registrar_atividade) do |_config, ctx|
      vistos << FluxoExecucao.find(ctx.execucao.id).trilha.size
      { saida: 's', resumo: 'ok' }
    end
    e = iniciar(grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'a' }], ['registrar_atividade', { 'texto' => 'b' }]))
    avancar(e)
    expect(vistos).to eq([1])
    expect(e.status).to eq('concluida')
  end
end
