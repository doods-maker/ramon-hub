require 'rails_helper'

RSpec.describe Ramon::Fluxos::Grafo do
  def grafo(dados) = described_class.new(dados)

  let(:valido) { grafo_linear({ 'tipo' => 'lead_criado' }, ['nota_privada', { 'texto' => 'oi' }]) }

  it 'navega pela saída' do
    g = grafo(valido)
    expect(g.gatilho['id']).to eq('g')
    expect(g.proximo('g', 's')).to eq('p1')
    expect(g.proximo('p1', 's')).to be_nil
  end

  it 'aceita desenho válido' do
    expect(grafo(valido).erros).to eq([])
  end

  it 'exige exatamente 1 gatilho conhecido' do
    expect(grafo({ 'nos' => [], 'setas' => [] }).erros).to include('O fluxo precisa de exatamente 1 gatilho')
    expect(grafo(grafo_linear({ 'tipo' => 'inventado' })).erros).to include('Gatilho desconhecido: inventado')
  end

  it 'recusa ciclo, passo solto e seta para passo inexistente' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['nota_privada', { 'texto' => 'a' }], ['nota_privada', { 'texto' => 'b' }])
    d['setas'] << { 'de' => 'p2', 'saida' => 's', 'para' => 'p1' }
    expect(grafo(d).erros).to include('O fluxo não pode voltar para um passo anterior')

    solto = grafo_linear({ 'tipo' => 'manual' })
    solto['nos'] << no_fluxo('x', 'nota_privada', { 'texto' => 'a' })
    expect(grafo(solto).erros).to include('Passo x não está ligado ao gatilho')

    fantasma = grafo_linear({ 'tipo' => 'manual' })
    fantasma['setas'] << { 'de' => 'g', 'saida' => 's', 'para' => 'zz' }
    expect(grafo(fantasma).erros).to include('Seta aponta para passo inexistente: zz')
  end

  it 'valida saídas de se e escolha' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['se', { 'condicoes' => [{ 'campo' => 'tese', 'operador' => 'existe' }] }])
    expect(grafo(d).erros).to include('Passo p1 (Se) precisa de pelo menos uma saída')

    e = grafo_linear({ 'tipo' => 'manual' },
                     ['escolha', { 'campo' => 'tese', 'casos' => [{ 'chave' => 'c1', 'rotulo' => 'A', 'valores' => ['x'] }] }])
    expect(grafo(e).erros).to include('Passo p1 (Escolha) precisa de pelo menos 2 casos')
  end

  it 'proíbe mensagem pública na ação do Chatwoot' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['acao_chatwoot', { 'acoes' => [{ 'action_name' => 'send_message' }] }])
    expect(grafo(d).erros).to include('Passo p1: mensagem ao cliente só como rascunho')
  end

  it 'recusa ação do Chatwoot fora da lista permitida' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['acao_chatwoot', { 'acoes' => [{ 'action_name' => 'system' }] }])
    expect(grafo(d).erros).to include('Passo p1: ação desconhecida (system)')
  end

  it 'recusa envio externo na ação do Chatwoot (webhook é passo próprio)' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['acao_chatwoot', { 'acoes' => [{ 'action_name' => 'send_webhook_event' }] }])
    expect(grafo(d).erros).to eq(['Passo p1: ação não permitida no fluxo (send_webhook_event)'])
  end

  it 'exige configuração obrigatória' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['mover_etapa', {}], ['esperar', {}])
    expect(grafo(d).erros).to include('Passo p1: falta etapa_id', 'Passo p2: falta o tempo de espera')
  end

  it 'aceita os gatilhos e passos da B2b' do
    d = grafo_linear({ 'tipo' => 'relogio', 'hora' => '09:00' },
                     ['registrar_atividade', { 'texto' => 'a' }], ['trocar_responsavel', { 'papel' => 'closer' }],
                     ['preencher_campo', { 'chave' => 'beneficio', 'valor' => 'BPC' }],
                     ['rascunho_ia', { 'instrucao' => 'Lembre dos documentos' }],
                     ['advbox', { 'acao' => 'movimentacao', 'descricao' => 'Contrato assinado no hub' }],
                     ['webhook', { 'url' => 'https://hooks.exemplo.com.br/x' }])
    expect(grafo(d).erros).to eq([])
  end

  it 'webhook: só https e só como último passo' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['webhook', { 'url' => 'http://hooks.exemplo.com.br' }], ['nota_privada', { 'texto' => 'a' }])
    expect(grafo(d).erros).to include('Passo p1: o webhook precisa de um endereço https://',
                                      'Passo p1 (Webhook) tem que ser o último passo')
  end

  it 'advbox: escolhe a ação e preenche o que cada uma pede' do
    sem_acao = grafo_linear({ 'tipo' => 'manual' }, ['advbox', {}])
    expect(grafo(sem_acao).erros).to eq(['Passo p1: escolha tarefa ou movimentação do ADVBOX'])
    tarefa = grafo_linear({ 'tipo' => 'manual' }, ['advbox', { 'acao' => 'tarefa' }])
    expect(grafo(tarefa).erros).to eq(['Passo p1: falta tipo_tarefa_id', 'Passo p1: falta responsavel_id'])
    curta = grafo_linear({ 'tipo' => 'manual' }, ['advbox', { 'acao' => 'movimentacao', 'descricao' => 'curta' }])
    expect(grafo(curta).erros).to eq(['Passo p1: a movimentação do ADVBOX precisa de pelo menos 10 letras'])
  end

  it 'perguntar à IA precisa de saída; preencher campo valida a chave; IA e skill têm obrigatórios' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['perguntar_ia', { 'pergunta' => 'Mandou o CNIS?' }])
    expect(grafo(d).erros).to eq(['Passo p1 (Perguntar à IA) precisa de pelo menos uma saída'])
    c = grafo_linear({ 'tipo' => 'manual' }, ['preencher_campo', { 'chave' => 'Benefício' }], ['rodar_skill', {}])
    expect(grafo(c).erros).to eq(['Passo p1: nome do campo só com letras minúsculas, números e _ (até 40)',
                                  'Passo p2: falta assistente_id', 'Passo p2: falta skill_id'])
  end

  it 'preencher campo recusa nome reservado do hub' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['preencher_campo', { 'chave' => 'nome' }])
    expect(grafo(d).erros).to eq(['Passo p1: nome é um nome reservado do hub'])
  end

  it 'relógio precisa da hora; hora torta é recusada; lead parado aceita sem hora' do
    expect(grafo(grafo_linear({ 'tipo' => 'relogio' })).erros).to eq(['O relógio precisa da hora (HH:MM)'])
    expect(grafo(grafo_linear({ 'tipo' => 'lead_parado', 'hora' => '25:00' })).erros).to eq(['Hora do gatilho inválida (use HH:MM)'])
    expect(grafo(grafo_linear({ 'tipo' => 'lead_parado' })).erros).to eq([])
  end

  it 'janela de horário inválida no Se ou no Esperar até o horário recusa publicar (B4.2)' do
    hc = { 'campo' => 'status', 'operador' => 'em_horario_comercial', 'dias' => [], 'inicio' => 7, 'fim' => 21 }
    se = grafo(grafo_linear({ 'tipo' => 'manual' }, ['se', { 'condicoes' => [hc] }]))
    espera = grafo(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'ate' => 'horario_comercial', 'inicio' => 20, 'fim' => 8 }]))
    boa = grafo(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'ate' => 'horario_comercial', 'dias' => [0, 6], 'inicio' => 7, 'fim' => 21 }]))
    expect(se.erros).to include('Passo p1: horário inválido (dias e início antes do fim)')
    expect(espera.erros).to eq(['Passo p1: horário inválido (dias e início antes do fim)'])
    expect(boa.erros).to eq([])
  end

  it 'esperar o SLA da caixa (a partir da criação da conversa) vale como tempo de espera (B4.2)' do
    sem_desde = grafo(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'prazo' => 'sla_caixa' }])).erros
    expect(sem_desde.join).to include('falta o tempo de espera')
    expect(grafo(grafo_linear({ 'tipo' => 'manual' }, ['esperar', { 'desde' => 'conversa', 'prazo' => 'sla_caixa' }])).erros).to eq([])
  end

  it 'rotina pronta precisa dizer qual rotina (B4.4)' do
    expect(grafo(grafo_linear({ 'tipo' => 'manual' }, ['rotina', {}])).erros).to eq(['Passo p1: falta rotina'])
  end

  describe 'Horário da conta (B5)' do
    def conta(gatilho, *passos) = grafo(grafo_linear({ 'tipo' => 'horario_conta' }.merge(gatilho), *passos)).erros

    it 'precisa de hora ou de a cada N minutos (1 a 1440) e de pelo menos um dia' do
      parar = ['parar', {}]
      expect([conta({ 'hora' => '08:00' }, parar), conta({ 'a_cada_minutos' => 1 }, parar)]).to eq([[], []])
      [{}, { 'a_cada_minutos' => 0 }, { 'a_cada_minutos' => 1441 }, { 'hora' => '08:00', 'dias' => [] },
       { 'hora' => '08:00', 'dias' => [7] }].each do |gatilho|
        expect(conta(gatilho, parar)).to eq([Ramon::Fluxos::HorarioConta::QUANDO])
      end
    end

    it 'só entram os passos que rodam sem lead; rotina de lead ou desconhecida não publica' do
      expect(conta({ 'hora' => '08:00' }, ['mover_etapa', { 'etapa_id' => 1 }]))
        .to eq(['Passo p1: precisa de um lead — neste gatilho só entram Se, Escolha, Esperar, Parar, Push e Rotina pronta'])
      expect(conta({ 'hora' => '08:00' }, ['rotina', { 'rotina' => 'dossie_passagem' }]))
        .to eq(['Passo p1: esta rotina não é da conta (precisa de um lead ou de outro evento) — não roda no Horário da conta'])
      expect(grafo(grafo_linear({ 'tipo' => 'manual' }, ['rotina', { 'rotina' => 'xyz' }])).erros)
        .to eq(['Passo p1: rotina desconhecida (xyz)'])
    end
  end

  describe 'gatilhos de fora do funil (alvo outro, sem lead)' do
    def erros_de(tipo, *passos) = grafo(grafo_linear({ 'tipo' => tipo }, *passos)).erros

    it 'passo que precisa de lead não publica (o sino numa peça publicada falharia em toda execução)' do
      expect(erros_de('peca_publicada', ['avisar_sino', { 'texto' => 'oi' }]))
        .to eq(['Passo p1: precisa de um lead — neste gatilho só entram Se, Escolha, Esperar, Parar, Push e Rotina pronta'])
      expect(erros_de('assinatura_painel', ['avisar_push', { 'texto' => 'oi' }], ['parar', {}])).to eq([])
    end

    it 'só rotina do mesmo alvo: de lead não entra aqui, a da chegada não entra em gatilho de lead' do
      outro_alvo = ['Passo p1: esta rotina é de outro alvo (lead ou evento de fora do funil) — não roda neste gatilho']
      expect(erros_de('chegada_cliente', ['rotina', { 'rotina' => 'dossie_passagem' }])).to eq(outro_alvo)
      expect(erros_de('manual', ['rotina', { 'rotina' => 'escalar_chegada' }])).to eq(outro_alvo)
    end

    it 'o desenho da Chegada de cliente (no ar: esperar → escalar a chegada) segue válido' do
      desenho = JSON.parse(Rails.root.join('db/seeds/ramon/fluxos/migrados/chegada_cliente.json').read)['desenho']
      expect(grafo(desenho).erros).to eq([])
    end
  end

  it 'N1 = B (08/10): os gatilhos de fora do funil seguem na paleta para fluxos comuns' do
    %w[assinatura_painel documento_painel reuniao_gravada peca_publicada peca_mudou_status].each do |tipo|
      expect(described_class.new(grafo_linear({ 'tipo' => tipo })).erros).to eq([])
    end
    expect(described_class::GATILHOS).to include('chegada_cliente', 'contrato_assinado', 'contrato_recusado', 'nota_escrita')
  end
end
