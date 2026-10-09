require 'rails_helper'

RSpec.describe Ramon::PortalNovidades do
  let(:anterior) { { 'id' => 1, 'etapa' => 'REQUERIMENTO PROTOCOLADO', 'etapa_cliente' => 'REQUERIMENTO PROTOCOLADO', 'andamentos' => [] } }

  def novo(etapa, andamentos = []) = { 'id' => 1, 'etapa' => etapa, 'andamentos' => andamentos }

  it 'sem espelho anterior não gera novidade' do
    expect(described_class.aplicar(nil, novo('PERICIA AGENDADA'))['novidades']).to eq([])
  end

  it 'mudança de etapa vira novidade comum; repetir o mesmo sync não duplica' do
    p = described_class.aplicar(anterior, novo('PERICIA AGENDADA'))
    expect(p['novidades'].map { |n| n.slice('tipo', 'delicada', 'vista', 'avisada') })
      .to eq([{ 'tipo' => 'etapa', 'delicada' => false, 'vista' => false, 'avisada' => false }])
    expect(described_class.aplicar(p, novo('PERICIA AGENDADA'))['novidades'].size).to eq 1
  end

  it 'etapa interna: o cliente segue vendo a anterior e nada é avisado' do
    p = described_class.aplicar(anterior, novo('NEGADO / AVISAR CLIENTE'))
    expect(p['etapa_cliente']).to eq 'REQUERIMENTO PROTOCOLADO'
    expect(p['novidades']).to eq([])
  end

  it 'etapa interna no 1º sync mostra texto neutro (etapa_cliente nil)' do
    expect(described_class.aplicar(nil, novo('NEGADO / AVISAR CLIENTE'))['etapa_cliente']).to be_nil
  end

  it 'etapa de resultado é delicada' do
    expect(described_class.aplicar(anterior, novo('DECISÃO PROFERIDA'))['novidades'].first['delicada']).to be true
  end

  it 'novidade de etapa leva a flag de e-mail do dicionário (v1 sempre true; v2 segue a tabela)' do
    expect(described_class.aplicar(anterior, novo('REUNIAO POS VENDA'))['novidades'].first['email']).to be true
    with_modified_env PORTAL_TEXTOS_V2: 'on' do
      base = { 'id' => 1, 'fase' => 'JUDICIAL', 'numero' => '0000498-04.2012.8.24.0044', 'andamentos' => [] }
      antes = described_class.aplicar(anterior, base.dup)
      sentenca = base.merge('andamentos' => [{ 'data' => '2026-10-01', 'titulo' => 'Julgado improcedente o pedido' }])
      expect(described_class.aplicar(antes, sentenca)['novidades'].find { |n| n['tipo'] == 'etapa' }['email']).to be false
    end
  end

  it 'marco novo vira novidade; espelho antigo sem etapa_cliente usa a etapa' do
    antigo = anterior.except('etapa_cliente')
    p = described_class.aplicar(antigo, novo('REQUERIMENTO PROTOCOLADO', [{ 'data' => '2026-09-20', 'titulo' => 'Perícia designada' }]))
    expect(p['novidades'].map { |n| [n['tipo'], n['titulo']] }).to eq([%w[marco Perícia]])
  end

  context 'with PORTAL_TEXTOS_V2=on (etapa do tribunal e das tarefas)' do
    around { |ex| with_modified_env(PORTAL_TEXTOS_V2: 'on') { ex.run } }

    let(:cnj) { '0000498-04.2012.8.24.0044' }
    let(:audiencia) { [{ 'tipo' => 'audiencia', 'quando' => '2027-03-09 16:00:00', 'formato' => 'presencial' }] }

    def judicial(extra = {}) = { 'id' => 1, 'etapa' => 'FASE DE INSTRUÇÃO', 'fase' => 'JUDICIAL', 'numero' => cnj, 'andamentos' => [] }.merge(extra)

    it 'a coluna do ADVBOX não manda: audiência marcada aparece mesmo com a etapa em instrução' do
      expect(described_class.aplicar(nil, judicial('agenda' => audiencia))['etapa_cliente']).to eq 'PAINEL AUDIENCIA MARCADA'
    end

    it '1º sync com a regra nova não avisa a troca; depois, audiência nova vira novidade com e-mail' do
      migrado = described_class.aplicar(anterior, judicial)
      expect(migrado['novidades']).to eq([])
      p = described_class.aplicar(migrado, judicial('agenda' => audiencia))
      expect(p['novidades'].map { |n| n.slice('tipo', 'titulo', 'email') })
        .to eq([{ 'tipo' => 'etapa', 'titulo' => 'Audiência marcada', 'email' => true }])
    end

    it 'o achado do tribunal fica no espelho quando o andamento sai da janela' do
      p = described_class.aplicar(nil, judicial('andamentos' => [{ 'data' => '2025-09-25', 'titulo' => 'Baixa Definitiva' }]))
      expect(described_class.aplicar(p, judicial)['etapa_cliente']).to eq 'ARQUIVADO/ENCERRADO'
    end
  end

  it 'descarta novidade vista e avisada há mais de 30 dias' do
    velha = { 'tipo' => 'etapa', 'vista' => true, 'avisada' => true, 'em' => 40.days.ago.iso8601 }
    recente = velha.merge('em' => 1.day.ago.iso8601)
    p = described_class.aplicar(anterior.merge('novidades' => [velha, recente]), novo('REQUERIMENTO PROTOCOLADO'))
    expect(p['novidades']).to eq([recente])
  end
end
