require 'rails_helper'

RSpec.describe Ramon::PerfilIa::Avisos do
  let(:account) { create(:account) }
  let!(:tese) { create(:thesis, account: account, zapsign_template_id: nil, honorario_na_tabela: false) }
  let(:alvo) { "tese:#{tese.id}" }

  def avisos = described_class.de(account.reload)
  def tipos(chave) = (avisos[chave] || []).pluck(:tipo)
  def perfis(secoes) = account.update!(settings: { 'ia_atendimento' => secoes })

  it 'tese que segue o padrão: sem modelo no ZapSign e fora da tabela; somem quando a causa some', :aggregate_failures do
    expect(avisos[alvo]).to eq([{ acao: 'contrato_zapsign', tipo: 'sem_zapsign', link: 'playbooks' },
                                { acao: 'citar_honorario', tipo: 'fora_da_tabela', link: 'playbooks' }])

    tese.update!(zapsign_template_id: 'modelo-1', honorario_na_tabela: true)
    expect(avisos).not_to have_key(alvo)
  end

  it 'permissão nunca não avisa (o perfil próprio da tese manda)' do
    perfis('teses' => { tese.id.to_s => { 'base' => 'cautelosa' } }) # cautelosa: honorário e contrato nunca

    expect(avisos).not_to have_key(alvo)
  end

  it 'marcar reunião sozinha sem nenhum Closer com Google: vale pra conta toda e some com o Google conectado', :aggregate_failures do
    perfis('padrao' => { 'base' => 'equilibrada' }) # equilibrada: marcar reunião sozinha
    expect(tipos('padrao')).to eq(['sem_google'])
    expect(tipos(alvo)).to include('sem_google')

    closer = create(:user, account: account)
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)
    expect(tipos('padrao')).to eq(['sem_google'])

    GoogleAgendaConta.create!(user: closer, account: account, refresh_token: 'rt', access_token: 'at')
    expect(avisos).not_to have_key('padrao')
    expect(tipos(alvo)).not_to include('sem_google')
  end

  it 'roteiro da tese sem saída Qualificado (fim); some com a saída concluir' do
    passo = create(:roteiro_passo, account: account, thesis: tese, saidas: [{ 'id' => 'a', 'quando' => '*', 'acao' => 'seguir' }])
    expect(avisos[alvo]).to include(acao: nil, tipo: 'sem_qualificado', link: 'roteiro')

    passo.update!(saidas: [{ 'id' => 'a', 'quando' => '*', 'acao' => 'concluir' }])
    expect(tipos(alvo)).not_to include('sem_qualificado')
  end

  it 'caixa com perfil e sem assistente conectado; sem perfil a caixa nem entra', :aggregate_failures do
    caixa = create(:inbox, account: account)
    perfis('caixas' => { caixa.id.to_s => { 'base' => 'cautelosa' } })
    expect(avisos["caixa:#{caixa.id}"]).to eq([{ acao: nil, tipo: 'sem_assistente', link: 'caixas' }])

    perfis('caixas' => {})
    expect(avisos).not_to have_key("caixa:#{caixa.id}")
  end
end
