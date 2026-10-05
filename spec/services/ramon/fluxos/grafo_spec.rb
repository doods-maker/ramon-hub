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

  it 'exige configuração obrigatória' do
    d = grafo_linear({ 'tipo' => 'manual' }, ['mover_etapa', {}], ['esperar', {}])
    expect(grafo(d).erros).to include('Passo p1: falta etapa_id', 'Passo p2: falta o tempo de espera')
  end
end
