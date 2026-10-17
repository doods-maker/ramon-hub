require 'rails_helper'

RSpec.describe 'Ramon IA Atendimento API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_ia_atendimento" }
  let(:tese) { create(:thesis, account: account) }

  def ler = account.reload.settings['ia_atendimento']

  def alterar(corpo, usuario = admin) = patch(url, params: corpo, headers: usuario.create_new_auth_token, as: :json)

  it 'agente não vê nem muda', :aggregate_failures do
    get url, headers: agente.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)

    alterar({ padrao: { base: 'acelerada' } }, agente)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'admin lê o catálogo e o que está salvo', :aggregate_failures do
    tese
    account.update!(settings: { 'ia_atendimento' => { 'teses' => { tese.id.to_s => { 'base' => 'acelerada' } } } })

    get url, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['prontos'].keys).to eq(%w[cautelosa equilibrada acelerada])
    expect(body['inicial']).to include('base' => 'cautelosa', 'marcador' => '_inicio')
    expect(body['padrao']).to eq(body['inicial'])
    expect(body['acoes'].pluck('chave')).to eq(Ramon::PerfilIa::ACOES)
    expect(body['acoes'].find { |a| a['chave'] == 'citar_honorario' }).to include('etapas' => %w[fase-qualificacao fase-negociacao])
    expect(body['acoes'].find { |a| a['chave'] == 'logistica' }).to include('sem_nunca' => true)
    expect(body['gatilhos'].find { |g| g['chave'] == 'irritado' }).to include('pendente' => true)
    expect(body['etapas'].pluck('chave')).to include('fase-novo', 'fase-qualificacao')
    expect(body['etapas'].pluck('chave')).not_to include(account.lead_stages.find_by(is_won: true).label.to_s)
    expect(body['teses']).to eq([{ 'id' => tese.id, 'nome' => tese.name, 'cfg' => { 'base' => 'acelerada' } }])
    expect(body['caixas']).to eq([])
  end

  it 'PATCH válido grava só os alvos enviados e devolve o corpo do GET', :aggregate_failures do
    outra = create(:thesis, account: account)
    account.update!(settings: { 'ia_atendimento' => { 'teses' => { outra.id.to_s => { 'base' => 'equilibrada' } } } })

    alterar({ padrao: { base: 'equilibrada', marcador: 'fase-qualificacao', permissoes: { citar_honorario: 'n' },
                        gatilhos: { 'fase-novo' => %w[pediu_pessoa irritado] } },
              teses: { tese.id.to_s => { base: 'acelerada' } } })

    expect(response).to have_http_status(:ok)
    expect(ler['padrao']).to include('base' => 'equilibrada', 'marcador' => 'fase-qualificacao')
    expect(ler['teses'][tese.id.to_s]).to eq('base' => 'acelerada')
    expect(ler['teses'][outra.id.to_s]).to eq('base' => 'equilibrada')
    expect(response.parsed_body['padrao']['permissoes']).to eq('citar_honorario' => 'n')

    alterar({ teses: { tese.id.to_s => nil } }) # null = volta a seguir o padrão
    expect(ler['teses'].keys).to eq([outra.id.to_s])
    expect(ler['padrao']['base']).to eq('equilibrada')
  end

  it 'PATCH inválido dá 422 e não grava nada', :aggregate_failures do
    estranha = create(:thesis, account: create(:account))
    antes = account.reload.settings
    invalidos = [
      { padrao: { base: 'xablau' } },
      { padrao: { permissoes: { logistica: 'n' } } },
      { padrao: { marcador: 'fase-que-nao-existe' } },
      { padrao: { gatilhos: { 'fase-novo' => %w[inventado] } } },
      { padrao: nil },
      { padrao: { base: 'acelerada' }, teses: { estranha.id.to_s => { base: 'acelerada' } } }
    ]
    invalidos.each do |corpo|
      alterar(corpo)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
      expect(account.reload.settings).to eq(antes)
    end
  end
end
