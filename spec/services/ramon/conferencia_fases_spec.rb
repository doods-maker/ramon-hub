require 'rails_helper'

RSpec.describe Ramon::ConferenciaFases do
  subject(:conferencia) { described_class.new(account, pausa: 0) }

  let(:account) { create(:account) }
  let(:cliente) { [{ 'name' => 'SIEMES ELISEU LINS', 'origin' => 'ESCRITÓRIO' }, { 'name' => 'INSS', 'origin' => 'PARTE CONTRÁRIA' }] }
  let(:cumprimento) do
    { 'id' => 1, 'process_number' => '5000939-49.2025.4.04.7216', 'stage' => 'SENTENÇA PROFERIDA', 'stages_id' => 3_736_269,
      'step' => 'JUDICIAL', 'responsible' => 'BRENDA ANTUNES', 'customers' => cliente }
  end
  let(:baixa) { cumprimento.merge('id' => 2, 'process_number' => '5000384-66.2024.4.04.7216', 'stage' => 'INICIAL / DEFESA PROTOCOLADA') }
  let(:administrativo) { cumprimento.merge('id' => 3, 'process_number' => nil, 'step' => 'ADMINISTRATIVO') }
  let(:carteira) { [cumprimento, baixa, administrativo] }
  let(:andamentos) do
    { 1 => [{ 'date' => '2026-06-10', 'title' => 'Classe Processual alterada - PARA: Cumprimento de Sentença contra a Fazenda Pública' }],
      2 => [{ 'date' => '2025-09-25', 'title' => 'Baixa Definitiva' }] }
  end

  around { |ex| with_modified_env(PORTAL_TEXTOS_V2: 'on') { ex.run } }

  before do
    allow(Ramon::AdvboxClient).to receive(:lawsuits) { { 'totalCount' => carteira.size, 'data' => carteira } }
    allow(Ramon::AdvboxClient).to receive(:last_movements) do
      { 'totalCount' => 2, 'data' => andamentos.map { |id, movs| { 'lawsuit_id' => id, 'date' => movs.first['date'] } } }
    end
    allow(Ramon::AdvboxClient).to receive(:movements) { |id, **| { 'data' => andamentos[id] } }
    allow(Ramon::AdvboxClient).to receive(:posts).and_return({ 'data' => [] })
    allow(Ramon::AdvboxClient).to receive(:settings).and_return(
      { 'stages' => [{ 'id' => 3_949_581, 'stage' => 'EXECUÇÃO COMO EXEQUENTE' }, { 'id' => 3_736_298, 'stage' => 'ARQUIVADO/ENCERRADO' }] }
    )
  end

  def linha(id) = account.ramon_conferencias_fase.find_by(lawsuit_id: id)

  it 'monta a carteira judicial ativa: etapa atrasada com sugestão e baixa no tribunal; pedido no INSS fica de fora' do
    conferencia.atualizar!
    expect(linha(1)).to have_attributes(grupo: 'atrasada', painel_titulo: 'Cobrança dos valores', fase_painel: 'pagamento',
                                        cliente: 'SIEMES ELISEU LINS', sugestao: { 'etapa' => 'EXECUÇÃO COMO EXEQUENTE', 'etapa_id' => 3_949_581 })
    expect(linha(2)).to have_attributes(grupo: 'baixa', sugestao: { 'etapa' => 'ARQUIVADO/ENCERRADO', 'etapa_id' => 3_736_298 })
    expect(linha(3)).to be_nil
  end

  it 'na noite seguinte só busca o que andou; etapa movida no ADVBOX vira "mesma fase"; arquivado sai da lista' do
    conferencia.atualizar!
    carteira.replace([cumprimento.merge('stage' => 'EXECUÇÃO COMO EXEQUENTE', 'step' => 'EXECUÇÃO/COBRANÇA')])
    described_class.new(account, pausa: 0).atualizar!
    expect(Ramon::AdvboxClient).to have_received(:movements).twice
    expect(linha(1)).to have_attributes(grupo: 'igual', sugestao: nil)
    expect(linha(2)).to be_nil
  end

  it 'sugestão nova desfaz a marcação antiga de atualizar' do
    conferencia.atualizar!
    linha(1).update!(atualizar: true)
    andamentos[1] = [{ 'date' => '2026-10-01', 'title' => 'Baixa Definitiva' }] + andamentos[1]
    described_class.new(account, pausa: 0).atualizar!
    expect(linha(1)).to have_attributes(grupo: 'baixa', atualizar: false)
  end

  it 'aplicar: grava a etapa sugerida no ADVBOX só das marcadas; erro fica na linha' do
    conferencia.atualizar!
    linha(1).update!(atualizar: true)
    linha(2).update!(atualizar: true)
    allow(Ramon::AdvboxClient).to receive(:update_lawsuit).with(1, stages_id: 3_949_581).and_return({})
    allow(Ramon::AdvboxClient).to receive(:update_lawsuit).with(2, stages_id: 3_736_298)
                                                          .and_raise(Ramon::AdvboxClient::RequestError.new(422, 'x'))
    conferencia.aplicar!(create(:user, account: account))
    expect(linha(1)).to have_attributes(etapa_advbox: 'EXECUÇÃO COMO EXEQUENTE', grupo: 'igual')
    expect(linha(1).aplicado_em).to be_present
    expect(linha(2)).to have_attributes(aplicado_em: nil, erro_aplicacao: 'AdvBox respondeu HTTP 422')
  end
end
