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
    # a conta já vem com teses do seed (cfg nil); o cfg salvo volta normalizado (listas vazias de permissões/gatilhos)
    linhas = body['teses'].index_by { |t| t['id'] }
    expect(linhas[tese.id]).to include('nome' => tese.name, 'cfg' => include('base' => 'acelerada'), 'assistente_id' => nil)
    expect(linhas.except(tese.id).values.pluck('cfg').uniq).to eq([nil])
    expect(body['caixas']).to eq([])
    # Números por Etapa (sem carimbo = sem dados) e o assistente do "Testar este perfil" (sem Captain no CI = nil)
    expect(body).to include('numeros' => {}, 'assistente_id' => nil)
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

  it 'GET traz os limites gerais; PATCH grava junto com o perfil (um save) e recusa o inválido', :aggregate_failures do
    get url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['limites']).to include(
      'atraso' => { 'min' => 30, 'max' => 180 }, 'retomadas_dia' => 15, 'retomada_intervalo_dias' => 5, 'teto_usd' => nil,
      'agente_dia' => AgenteExecucao::TETO_DIA, 'horario' => { 'dias' => [1, 2, 3, 4, 5], 'janelas' => [%w[08:30 12:00], %w[13:30 18:00]] }
    )

    alterar({ padrao: { base: 'acelerada' }, limites: { atraso: { min: 10, max: 90 }, retomadas_dia: 25, teto_usd: 3 } })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['limites']).to include('atraso' => { 'min' => 10, 'max' => 90 }, 'retomadas_dia' => 25, 'teto_usd' => 3.0)
    expect(ler['padrao']['base']).to eq('acelerada')

    antes = account.reload.settings
    alterar({ padrao: { base: 'equilibrada' }, limites: { atraso: { min: 10, max: 200 } } })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to be_present
    expect(account.reload.settings).to eq(antes)
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

  it 'GET traz os avisos de dependência e a caixa com perfil mesmo sem assistente', :aggregate_failures do
    tese # criada antes do GET (let preguiçoso)
    caixa = create(:inbox, account: account)
    account.update!(settings: { 'ia_atendimento' => { 'caixas' => { caixa.id.to_s => { 'base' => 'cautelosa' } } } })

    get url, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['caixas']).to eq([{ 'id' => caixa.id, 'nome' => caixa.name, 'cfg' => { 'base' => 'cautelosa', 'permissoes' => {}, 'gatilhos' => {} },
                                    'assistente_id' => nil }])
    expect(body['avisos']["caixa:#{caixa.id}"]).to eq([{ 'acao' => nil, 'tipo' => 'sem_assistente', 'link' => 'caixas' }])
    expect(body['avisos']["tese:#{tese.id}"].pluck('tipo')).to eq(%w[sem_zapsign fora_da_tabela])
  end

  describe 'POST desfazer' do
    let(:antes) { { 'ia_atendimento' => { 'teses' => { tese.id.to_s => { 'base' => 'acelerada' } } } } }
    let(:depois) { { 'ia_atendimento' => { 'teses' => { tese.id.to_s => { 'base' => 'equilibrada' } } } } }

    def auditar(conta = account, settings_antes = antes)
      Audited.audit_class.create!(auditable: conta, associated: conta, action: 'update', audited_changes: { 'settings' => [settings_antes, depois] })
    end

    def desfazer(audit, alvo, usuario = admin)
      post "#{url}/desfazer", params: { audit_id: audit.id, alvo: alvo }, headers: usuario.create_new_auth_token, as: :json
    end

    it 'regrava o valor de antes do alvo' do
      account.update!(settings: depois)
      desfazer(auditar, "tese:#{tese.id}")

      expect(response).to have_http_status(:no_content)
      expect(ler['teses'][tese.id.to_s]).to eq('base' => 'acelerada')
    end

    it 'agente não desfaz; linha de outra conta = 404; valor que não vale mais = 422 com a mensagem', :aggregate_failures do
      desfazer(auditar, "tese:#{tese.id}", agente)
      expect(response).to have_http_status(:unauthorized)

      desfazer(auditar(create(:account)), "tese:#{tese.id}")
      expect(response).to have_http_status(:not_found)

      desfazer(auditar(account, { 'ia_atendimento' => { 'teses' => { tese.id.to_s => { 'base' => 'xablau' } } } }), "tese:#{tese.id}")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('base desconhecida')
    end
  end
end
