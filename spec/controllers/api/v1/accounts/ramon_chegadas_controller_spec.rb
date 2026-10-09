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

  describe 'a decisão da chegada (Migracao.decidir + Disparo.externo — B5-externos)' do
    def migrado = Ramon::Fluxos::Migracao.fluxo(account, 'chegada_cliente')
    def chegada = Chegada.find(response.parsed_body['id'])

    it 'criar = o fluxo da chegada (o único de fora do funil no fluxo, 08/10), em sombra, ligado e publicado' do
      fluxos = Ramon::Fluxos::Migracao.semear(account, 'chegada_cliente')
      expect(fluxos.map { |f| [f.sistema_chave, f.gatilho_tipo, f.origem, f.modo, f.ativo, f.versao_publicada.present?] })
        .to eq([['chegada_cliente', 'chegada_cliente', 'usuario', 'sombra', true, true]])
      expect(Ramon::Fluxos::Migracao.descrever(account, 'chegada_cliente')).to include('o CÓDIGO faz a escalada da chegada de cliente')
      expect(Ramon::Fluxos::Disparo::DUAS_VEZES).to include('chegada_cliente')
    end

    it 'código no comando (padrão): o código agenda; o migrado só ensaia; o fluxo comum do gatilho ouve sem a decisão' do
      Ramon::Fluxos::Migracao.semear(account, 'chegada_cliente')
      comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'chegada_cliente' }))
      avisar
      expect(Ramon::ChegadaEscalarJob).to have_been_enqueued.with(chegada.id).once
      expect(migrado.execucoes.pluck(:ensaio)).to eq([true])
      expect(comum.execucoes.map { |e| [e.ensaio, e.contexto['gatilho'].key?('assumido')] }).to eq([[false, false]])
    end

    it 'fluxo no comando mas o motor falhou: o código agenda aquela chegada (reserva) — nunca nenhum' do
      with_modified_env(RAMON_FLUXO_CHEGADA: 'on') do
        Ramon::Fluxos::Migracao.semear(account, 'chegada_cliente')
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'chegada_cliente', 'normal')
        allow(Ramon::Fluxos::Disparo).to receive(:call).and_raise(StandardError, 'motor')
        avisar
      end
      expect(response).to have_http_status(:success)
      expect(Ramon::ChegadaEscalarJob).to have_been_enqueued.with(chegada.id).once
      expect(migrado.execucoes.count).to eq(0)
    end
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
