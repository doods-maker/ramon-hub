require 'rails_helper'

RSpec.describe Ramon::PerfilIa::Gravacao do
  let(:account) { create(:account) }
  let(:tese) { create(:thesis, account: account) }

  def expect_recusa(alvos, motivo)
    expect { Ramon::PerfilIa.gravar!(account, alvos) }.to raise_error(ArgumentError, motivo)
    expect(account.reload.settings['ia_atendimento']).to be_nil
  end

  it 'recusa cada tipo de entrada inválida sem gravar', :aggregate_failures do
    expect_recusa({ 'padrao' => nil }, /configuração inválida/)
    expect_recusa({ 'padrao' => { 'base' => 'xablau' } }, /base desconhecida/)
    expect_recusa({ 'padrao' => { 'permissoes' => { 'voar' => 's' } } }, /ação desconhecida/)
    expect_recusa({ 'padrao' => { 'permissoes' => { 'logistica' => 'x' } } }, /permissão inválida/)
    expect_recusa({ 'padrao' => { 'permissoes' => { 'fora_do_horario' => 'n' } } }, /não aceita nunca/)
    expect_recusa({ 'padrao' => { 'marcador' => 'fase-ganho-inexistente' } }, /marcador desconhecido/)
    expect_recusa({ 'padrao' => { 'gatilhos' => { 'etapa-x' => [] } } }, /etapa desconhecida/)
    expect_recusa({ 'padrao' => { 'gatilhos' => { 'fase-novo' => ['inventado'] } } }, /gatilho desconhecido/)
    expect_recusa({ 'teses' => { '0' => { 'base' => 'acelerada' } } }, /não é desta conta/)
    expect_recusa({ 'caixas' => { '0' => { 'base' => 'acelerada' } } }, /não é desta conta/)
  end

  it 'aceita Marcador de Etapa aberta, _fim e gatilho pendente; não mexe no que não foi enviado', :aggregate_failures do
    account.update!(settings: { 'ia_atendimento' => { 'padrao' => { 'base' => 'equilibrada' } } })
    described_class.gravar!(account, 'teses' => { tese.id.to_s => { 'marcador' => '_fim', 'gatilhos' => { 'fase-novo' => ['irritado'] } } })
    salvo = account.reload.settings['ia_atendimento']
    expect(salvo['padrao']).to eq('base' => 'equilibrada')
    expect(salvo['teses'][tese.id.to_s]['gatilhos']).to eq('fase-novo' => ['irritado'])
  end
end
