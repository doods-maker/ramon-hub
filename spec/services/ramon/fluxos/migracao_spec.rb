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

  describe '.decidir: a decisão do evento, lida uma vez, com reserva (SLA e chegada usam)' do
    let(:conversa) { create(:conversation, account: account) }
    let(:fluxo) do
      fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada' }, ['parar', {}]),
                      sistema_chave: 'sla_primeira_resposta', modo: 'normal')
    end

    it 'código no comando (chave desligada): o bloco roda e o fluxo do grupo só ensaia' do
      fluxo
      expect { |b| described_class.decidir('sla', 'conversa_criada', conversa, {}, &b) }.to yield_control.once
      expect(fluxo.execucoes.sole.ensaio).to be(true)
    end

    it 'fluxo no comando que pegou o evento: o bloco não roda (nunca em dobro)' do
      fluxo
      with_modified_env(RAMON_FLUXO_SLA: 'on') do
        expect { |b| described_class.decidir('sla', 'conversa_criada', conversa, {}, &b) }.not_to yield_control
      end
      expect(fluxo.execucoes.sole.ensaio).to be(false)
    end

    it 'fluxo no comando que NÃO pegou o evento (ocupado com a mesma conversa): o bloco roda (reserva, nunca nenhum)' do
      fluxo.execucoes.create!(account: account, alvo: conversa, status: 'esperando', retomar_em: 5.minutes.from_now)
      with_modified_env(RAMON_FLUXO_SLA: 'on') do
        expect { |b| described_class.decidir('sla', 'conversa_criada', conversa, {}, &b) }.to yield_control.once
      end
      expect(fluxo.execucoes.count).to eq(1)
    end

    it 'motor com erro: o bloco roda (o Disparo.externo engole o erro e devolve [])' do
      allow(Ramon::Fluxos::Disparo).to receive(:call).and_raise(StandardError, 'motor')
      with_modified_env(RAMON_FLUXO_SLA: 'on') do
        fluxo
        expect { |b| described_class.decidir('sla', 'conversa_criada', conversa, {}, &b) }.to yield_control.once
      end
    end
  end

  it 'os 9 desenhos migrados (db/seeds/ramon/fluxos/migrados) seguem válidos, cada um no gatilho do seu grupo' do
    fluxos = described_class::GRUPOS.keys.flat_map { |nome| described_class.semear(account, nome) }
    expect(fluxos.map(&:sistema_chave)).to match_array(described_class::PASTA.glob('*.json').map { |f| f.basename('.json').to_s })
    expect(fluxos.size).to eq(9)
    erros = fluxos.to_h { |f| [f.sistema_chave, Ramon::Fluxos::Grafo.new(f.versao_publicada.grafo).erros] }
    expect(erros.reject { |_chave, lista| lista.empty? }).to eq({})
    expect(fluxos.to_h { |f| [f.sistema_chave, f.gatilho_tipo] }).to eq(described_class::GRUPOS.values.map { |g| g[:fluxos] }.reduce(:merge))
  end

  it 'as 16 regras fixas de 08/10 não são mais migração; sobram as 7 que rodam no fluxo' do
    fixas = %w[criar_lead origem_lead sugestao_doc coach agente retrato_funil fechamento_extrato espelho_painel
               copiloto_noturno publicar_pecas avisos_painel assinatura_painel contrato_zapsign documento_painel
               ata_reuniao acervo_pecas]
    expect(described_class::GRUPOS.keys & fixas).to eq([])
    expect(described_class::GRUPOS.keys)
      .to match_array(%w[reunioes sla cadencia lead_ganho eventos_advbox resumo_do_dia chegada_cliente])
  end
end
