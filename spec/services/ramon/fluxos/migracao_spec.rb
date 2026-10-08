require 'rails_helper'

RSpec.describe Ramon::Fluxos::Migracao do
  let(:account) { create(:account) }

  it 'migração desconhecida é recusada com a lista das que existem' do
    expect { described_class.assumiu?(account, 'xyz') }.to raise_error(ArgumentError, /desconhecida: xyz.*reunioes/)
  end

  it 'migrado? = fluxo próprio (origem usuario) com a chave de uma migração; o desenho do sistema e os demais não' do
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: 'lembretes_reuniao'))).to be(true)
    expect(described_class.migrado?(Fluxo.new(origem: 'sistema', sistema_chave: 'lembretes_reuniao'))).to be(false)
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: nil))).to be(false)
  end

  it 'a API genérica e a das reuniões são a mesma coisa' do
    expect(described_class.gatilhos('reunioes')).to eq(Ramon::Fluxos::Reunioes::GATILHOS)
    expect(described_class.descrever(account, 'reunioes')).to eq('Agora o CÓDIGO faz o agendamento (os fluxos ensaiam).')
  end

  it 'grupo com limite_devolve: false segue no comando mesmo com limite do dia (o código também tem teto)' do
    teste = { env: 'RAMON_FLUXO_TESTE', faz: 'o teste', fluxos: { 'teste_limite' => 'lead_criado' }.freeze, limite_devolve: false }
    stub_const("#{described_class}::GRUPOS", described_class::GRUPOS.merge('teste' => teste))
    grafo = grafo_linear({ 'tipo' => 'lead_criado' }, ['parar', {}])
    fluxo_publicado(account, grafo, sistema_chave: 'teste_limite', modo: 'normal', limite_dia: 15)
    with_modified_env(RAMON_FLUXO_TESTE: 'on') { expect(described_class.assumiu?(account, 'teste')).to be(true) }
  end

  it 'SLA (B4.2): criar = 1 fluxo em sombra, ligado e publicado; virar exige RAMON_FLUXO_SLA; cada migração tem a sua chave' do
    fluxos = described_class.semear(account, 'sla')
    expect(fluxos.map { |f| [f.sistema_chave, f.gatilho_tipo, f.modo, f.ativo, f.versao_publicada_id.present?] })
      .to eq([['sla_primeira_resposta', 'conversa_criada', 'sombra', true, true]])
    expect { described_class.mudar_modo!(account, 'sla', 'normal') }.to raise_error(ArgumentError, /RAMON_FLUXO_SLA/)
    with_modified_env(RAMON_FLUXO_SLA: 'on') do
      expect(described_class.assumiu?(account, 'sla')).to be(false) # ainda em sombra
      described_class.mudar_modo!(account, 'sla', 'normal')
      expect(described_class.assumiu?(account, 'sla')).to be(true)
      expect(described_class.assumiu?(account, 'reunioes')).to be(false)
    end
    expect(described_class.descrever(account, 'sla')).to include('Agora o CÓDIGO faz o aviso de SLA da 1ª resposta')
  end

  it 'lead ganho e eventos do ADVBOX (B4.4/B4.5): cada migração com a sua chave e o seu gatilho' do
    fluxo_publicado(account, grafo_linear({ 'tipo' => 'lead_ganho' }, ['parar', {}]), sistema_chave: 'lead_ganho', modo: 'normal')
    fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox' }, ['parar', {}]), sistema_chave: 'eventos_advbox', modo: 'normal')
    with_modified_env(RAMON_FLUXO_LEAD_GANHO: 'on') do
      expect(described_class.assumiu?(account, 'lead_ganho')).to be(true)
      expect(described_class.assumiu?(account, 'eventos_advbox')).to be(false) # sem RAMON_FLUXO_EVENTOS_ADVBOX
    end
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: 'eventos_advbox'))).to be(true)
  end

  it 'leads e conversas (B5-leads): 5 migrações, cada uma com a sua chave e o seu gatilho' do
    esperado = {
      'criar_lead' => ['RAMON_FLUXO_CRIAR_LEAD', { 'criar_lead_da_conversa' => 'conversa_criada' }],
      'origem_lead' => ['RAMON_FLUXO_ORIGEM_LEAD', { 'origem_do_lead' => 'mensagem_recebida' }],
      'sugestao_doc' => ['RAMON_FLUXO_SUGESTAO_DOC', { 'sugestao_documento' => 'mensagem_recebida' }],
      'coach' => ['RAMON_FLUXO_COACH', { 'coach_objecao' => 'mensagem_recebida' }],
      'agente' => ['RAMON_FLUXO_AGENTE', { 'agente_hub' => 'nota_escrita' }]
    }
    expect(esperado.keys.to_h { |g| [g, [described_class.grupo(g)[:env], described_class.gatilhos(g)]] }).to eq(esperado)
  end

  describe '.decidir (B5-leads): a decisão do evento, lida uma vez, com reserva' do
    let(:conversa) { create(:conversation, account: account) }
    let(:fluxo) do
      fluxo_publicado(account, grafo_linear({ 'tipo' => 'mensagem_recebida' }, ['parar', {}]), sistema_chave: 'coach_objecao', modo: 'normal')
    end

    it 'código no comando (chave desligada): o bloco roda e o fluxo do grupo só ensaia' do
      fluxo
      expect { |b| described_class.decidir('coach', 'mensagem_recebida', conversa, {}, &b) }.to yield_control.once
      expect(fluxo.execucoes.sole.ensaio).to be(true)
    end

    it 'fluxo no comando que pegou o evento: o bloco não roda (nunca em dobro)' do
      fluxo
      with_modified_env(RAMON_FLUXO_COACH: 'on') do
        expect { |b| described_class.decidir('coach', 'mensagem_recebida', conversa, {}, &b) }.not_to yield_control
      end
      expect(fluxo.execucoes.sole.ensaio).to be(false)
    end

    it 'fluxo no comando que NÃO pegou o evento (ocupado com a mesma conversa): o bloco roda (reserva, nunca nenhum)' do
      fluxo.execucoes.create!(account: account, alvo: conversa, status: 'esperando', retomar_em: 5.minutes.from_now)
      with_modified_env(RAMON_FLUXO_COACH: 'on') do
        expect { |b| described_class.decidir('coach', 'mensagem_recebida', conversa, {}, &b) }.to yield_control.once
      end
      expect(fluxo.execucoes.count).to eq(1)
    end

    it 'motor com erro: o bloco roda (o Disparo.externo engole o erro e devolve [])' do
      allow(Ramon::Fluxos::Disparo).to receive(:call).and_raise(StandardError, 'motor')
      with_modified_env(RAMON_FLUXO_COACH: 'on') do
        fluxo
        expect { |b| described_class.decidir('coach', 'mensagem_recebida', conversa, {}, &b) }.to yield_control.once
      end
    end
  end
end
