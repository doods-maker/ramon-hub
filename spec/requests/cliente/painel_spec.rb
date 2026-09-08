require 'rails_helper'

RSpec.describe 'Painel do cliente — painel', type: :request do
  let(:account) { create(:account) }
  let(:processos) do
    [{ 'id' => 1, 'numero' => '5003800-40.2022.4.04.7207', 'tipo' => 'AUXÍLIO-ACIDENTE', 'inicio' => '2022-05-02',
       'responsavel' => 'RAMON ANTONIO', 'responsavel_id' => 259_713, 'etapa' => 'PERICIA AGENDADA', 'fase' => 'ADMINISTRATIVO',
       'andamentos' => [{ 'data' => '2026-06-01', 'titulo' => 'Perícia realizada' }],
       'docs_pendentes' => [{ 'item' => 'CNIS atualizado', 'post_id' => 9 }] },
     { 'id' => 2, 'numero' => '000', 'tipo' => 'PENSÃO', 'etapa' => 'ARQUIVADO/ENCERRADO', 'fase' => 'ARQUIVAMENTO',
       'andamentos' => [], 'docs_pendentes' => [] }]
  end
  let(:cliente) { create(:portal_cliente, account: account, convidado_em: 1.day.ago, termos_aceitos_em: 1.day.ago, processos: processos) }

  def entrar(alvo = cliente)
    post '/cliente/entrar', params: { email: alvo.email, codigo: alvo.gerar_codigo! }
  end

  it 'sem sessão redireciona pro login' do
    get '/cliente/inicio'
    expect(response).to redirect_to('/cliente')
  end

  it 'primeiro acesso pede aceite dos termos e grava o timestamp' do
    cliente.update!(termos_aceitos_em: nil)
    entrar
    get '/cliente/inicio'
    expect(response.body).to include('Termos de uso')
    post '/cliente/termos', params: { aceite: '1' }
    expect(cliente.reload.termos_aceitos_em).to be_present
    expect(response).to redirect_to('/cliente/inicio')
  end

  it 'lista ativos e encerrados com a etapa traduzida' do
    entrar
    get '/cliente/inicio'
    expect(response.body).to include('Perícia agendada')
    expect(response.body).to include('Encerrados')
    expect(response.body).to include('Processo encerrado')
    expect(response.body).not_to include('ARQUIVADO/ENCERRADO')
  end

  it 'tela do processo mostra marcos, identificação e pendências' do
    entrar
    get '/cliente/processos/1'
    expect(response.body).to include('Perícia')
    expect(response.body).to include('5003800-40.2022.4.04.7207')
    expect(response.body).to include('CNIS atualizado')
    expect(response.body).to include('Falta 1 documento')
  end

  it 'processo de outro cliente dá 404' do
    entrar
    get '/cliente/processos/999'
    expect(response).to have_http_status(:not_found)
  end

  it 'atualizar chama o sync uma vez e bloqueia a segunda em menos de 6h' do
    sync = instance_double(Ramon::PortalSyncService, perform: [])
    allow(Ramon::PortalSyncService).to receive(:new).and_return(sync)
    entrar
    post '/cliente/atualizar'
    post '/cliente/atualizar'
    expect(sync).to have_received(:perform).once
    expect(response).to redirect_to('/cliente/inicio')
  end

  describe 'POST /cliente/processos/:id/envios' do
    let(:pdf) { fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') }

    it 'grava o envio com o pedido e enfileira o job' do
      entrar
      expect do
        post '/cliente/processos/1/envios', params: { file: pdf, item: 'CNIS atualizado', post_id: 9 }
      end.to change(PortalEnvio, :count).by(1).and have_enqueued_job(Ramon::PortalEnvioJob)
      envio = PortalEnvio.last
      expect(envio.solicitacao_post_id).to eq 9
      expect(envio.arquivo).to be_attached
      expect(response).to redirect_to('/cliente/processos/1')
      get '/cliente/processos/1'
      expect(response.body).to include('Enviado — em conferência')
    end

    it 'recusa arquivo com content_type mentiroso' do
      entrar
      falso = fixture_file_upload(Rails.root.join('spec/assets/sample.mp3'), 'application/pdf')
      expect { post '/cliente/processos/1/envios', params: { file: falso, item: 'CNIS', post_id: 9 } }.not_to change(PortalEnvio, :count)
      expect(response).to redirect_to('/cliente/processos/1')
    end
  end
end
