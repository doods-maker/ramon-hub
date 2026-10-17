require 'rails_helper'

RSpec.describe Ramon::PerfilIa::Migracao do
  let(:account) { create(:account) }
  let(:perfis) { -> { account.reload.settings['ia_atendimento'] } }
  let(:inicial) { Ramon::PerfilIa::INICIAL }

  def caixa(modo, tese: nil)
    create(:inbox, account: account).tap { |i| i.update!(ramon_copiloto_modo: modo, ramon_thesis_id: tese&.id) }
  end

  def conversa(attrs)
    create(:conversation, account: account, inbox: create(:inbox, account: account), custom_attributes: attrs)
  end

  it 'mapeia o modo de cada caixa sem tese para caixas[id]', :aggregate_failures do
    rasc = caixa('rascunho')
    lim = caixa('piloto_limitado')
    qual = caixa('piloto_ate_qualificacao')
    reun = caixa('piloto_ate_reuniao')
    cont = caixa('piloto_ate_contrato')
    total = caixa('piloto_total')
    caixa('manual')
    caixa(nil)
    resultado = described_class.rodar(account)
    caixas = perfis.call['caixas']
    expect(caixas.keys).to match_array([rasc, lim, qual, reun, cont, total].map { |i| i.id.to_s })
    expect(caixas[rasc.id.to_s]).to eq(inicial.deep_merge('permissoes' => { 'logistica' => 'r' }))
    expect(caixas[lim.id.to_s]).to eq(inicial)
    expect(caixas[qual.id.to_s]).to eq('base' => 'cautelosa')
    expect(caixas[reun.id.to_s]).to eq('base' => 'equilibrada')
    expect(caixas[cont.id.to_s]).to eq('base' => 'acelerada')
    expect(caixas[total.id.to_s]).to eq('base' => 'acelerada')
    expect(resultado).to include(padrao: 'gravado', caixas: 6, teses: 0, descartadas: [])
    expect(perfis.call['padrao']).to eq(inicial)
  end

  it 'caixa com tese vai para teses[tese_id]; tese que já tem perfil descarta' do
    tese = create(:thesis, account: account)
    caixa('piloto_total', tese: tese)
    segunda = caixa('piloto_ate_reuniao', tese: tese)
    resultado = described_class.rodar(account)
    expect(perfis.call['teses']).to eq(tese.id.to_s => { 'base' => 'acelerada' })
    expect(perfis.call['caixas']).to be_blank
    expect(resultado[:teses]).to eq(1)
    expect(resultado[:descartadas]).to eq([{ caixa: segunda.id, modo: 'piloto_ate_reuniao', motivo: 'tese já tinha perfil' }])
  end

  it 'mantém perfil já gravado de caixa e do padrão, e informa o descarte' do
    outra = caixa('piloto_total')
    account.update!(settings: { 'ia_atendimento' => { 'padrao' => { 'base' => 'equilibrada' },
                                                      'caixas' => { outra.id.to_s => { 'base' => 'cautelosa' } } } })
    resultado = described_class.rodar(account)
    expect(perfis.call['padrao']).to eq('base' => 'equilibrada')
    expect(perfis.call['caixas'][outra.id.to_s]).to eq('base' => 'cautelosa')
    expect(resultado).to include(padrao: 'mantido', caixas: 0)
    expect(resultado[:descartadas]).to eq([{ caixa: outra.id, modo: 'piloto_total', motivo: 'caixa já tinha perfil' }])
  end

  it 'conversa manual vira pausada e as chaves antigas saem' do
    c = conversa('copiloto_modo' => 'manual', 'outra' => 1)
    resultado = described_class.rodar(account)
    expect(c.reload.custom_attributes).to eq('ia_pausa' => 'pausada', 'outra' => 1)
    expect(resultado).to include(conversas_pausadas: 1, conversas_rascunho: 0)
  end

  it 'conversa rascunho vira Pausa rascunho, com ou sem modo guardado, salvo se veio de limite' do
    com = conversa('copiloto_modo' => 'rascunho', 'copiloto_modo_antes_roteiro' => 'piloto_total')
    sem = conversa('copiloto_modo' => 'rascunho')
    limite = conversa('copiloto_modo' => 'rascunho', 'copiloto_limite' => { 'limite' => 'x' })
    resultado = described_class.rodar(account)
    expect(com.reload.custom_attributes).to eq('ia_pausa' => 'rascunho', 'ia_pausa_antes_roteiro' => nil)
    expect(sem.reload.custom_attributes).to eq('ia_pausa' => 'rascunho')
    expect(limite.reload.custom_attributes).to eq('copiloto_limite' => { 'limite' => 'x' })
    expect(resultado).to include(conversas_pausadas: 0, conversas_rascunho: 2)
  end

  it 'leva o modo de antes do roteiro para a Pausa guardada' do
    man = conversa('copiloto_modo' => 'piloto_total', 'copiloto_modo_antes_roteiro' => 'manual')
    ras = conversa('copiloto_modo' => 'piloto_total', 'copiloto_modo_antes_roteiro' => 'rascunho')
    pil = conversa('copiloto_modo_antes_roteiro' => 'piloto_limitado')
    described_class.rodar(account)
    expect(man.reload.custom_attributes).to eq('ia_pausa_antes_roteiro' => 'pausada')
    expect(ras.reload.custom_attributes).to eq('ia_pausa_antes_roteiro' => 'rascunho')
    expect(pil.reload.custom_attributes).to eq('ia_pausa_antes_roteiro' => nil)
  end

  it 'é idempotente' do
    caixa('piloto_total')
    conversa('copiloto_modo' => 'manual')
    described_class.rodar(account)
    antes = [account.reload.settings, Conversation.pluck(:custom_attributes)]
    resultado = described_class.rodar(account)
    expect([account.reload.settings, Conversation.pluck(:custom_attributes)]).to eq(antes)
    expect(resultado).to eq(padrao: 'mantido', caixas: 0, teses: 0, descartadas: [], conversas_pausadas: 0, conversas_rascunho: 0)
  end
end
