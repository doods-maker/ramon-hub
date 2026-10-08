require 'rails_helper'

RSpec.describe 'Ramon Chegadas API', type: :request do
  let(:account) { create(:account) }
  let(:gabriela) { create(:user, account: account, role: :agent) }
  let(:brenda) { create(:user, account: account, role: :agent) }
  let(:outro) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_chegadas" }

  before do
    time = create(:team, account: account, name: Chegada::RECEPCAO)
    create(:team_member, team: time, user: gabriela)
  end

  def avisar(user = gabriela)
    post url, params: { cliente_nome: 'Maria', motivo: 'Assinatura', destinatario_id: brenda.id },
              headers: user.create_new_auth_token, as: :json
  end

  it 'recepção avisa e agenda a escalada' do
    expect { avisar }.to have_enqueued_job(Ramon::ChegadaEscalarJob)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('cliente_nome' => 'Maria', 'estado' => 'aguardando')
    expect(response.parsed_body['destinatario']).to include('id' => brenda.id)
  end

  it 'fluxo "Chegada de cliente" no comando: o código não agenda; o fluxo espera 3 min e escala (o alerta volta ao vivo)' do
    with_modified_env(RAMON_FLUXO_CHEGADA: 'on') do
      Ramon::Fluxos::Migracao.semear(account, 'chegada_cliente')
      Ramon::Fluxos::Migracao.mudar_modo!(account, 'chegada_cliente', 'normal')
      expect { avisar }.not_to have_enqueued_job(Ramon::ChegadaEscalarJob)
    end
    chegada = Chegada.find(response.parsed_body['id'])
    perform_enqueued_jobs(only: Ramon::FluxoAvancarJob)
    execucao = Ramon::Fluxos::Migracao.fluxo(account, 'chegada_cliente').execucoes.sole
    expect(execucao).to have_attributes(status: 'esperando', ensaio: false)
    expect(execucao.retomar_em).to be_within(10.seconds).of(3.minutes.from_now)
    travel(3.minutes + 1.second) do
      perform_enqueued_jobs(only: Ramon::FluxoAvancarJob) { Ramon::FluxoRelogioJob.perform_now }
    end
    expect(chegada.reload.estado).to eq('escalado')
  end

  it 'agente fora da recepção não avisa' do
    avisar(outro)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'só o destinatário responde' do
    avisar
    id = response.parsed_body['id']

    post "#{url}/#{id}/responder", params: { resposta: 'x' }, headers: outro.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    post "#{url}/#{id}/responder", params: { resposta: 'Já vou' }, headers: brenda.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('estado' => 'respondido', 'resposta' => 'Já vou')
  end

  it 'index: recepção vê todas e pode avisar; os demais só as suas' do
    avisar
    get url, headers: gabriela.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('pode_avisar' => true)
    expect(response.parsed_body['payload'].size).to eq(1)

    get url, headers: outro.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('pode_avisar' => false, 'payload' => [])

    get url, headers: brenda.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].size).to eq(1)
  end

  it 'agenda devolve 503 com ADVBOX fora' do
    allow(Ramon::AdvboxClient).to receive(:posts).and_raise(Ramon::AdvboxClient::UnavailableError)
    get "#{url}/agenda", headers: gabriela.create_new_auth_token, as: :json
    expect(response).to have_http_status(:service_unavailable)
  end
end
