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
    post '/cliente/entrar', params: { cpf: alvo.cpf, senha: alvo.gerar_senha_provisoria! }
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

  context 'with PORTAL_TEXTOS_V2=on' do
    around { |ex| with_modified_env(PORTAL_TEXTOS_V2: 'on') { ex.run } }

    it 'termos v2 e, depois do aceite, as 3 telas de boas-vindas' do
      cliente.update!(termos_aceitos_em: nil)
      entrar
      get '/cliente/inicio'
      expect(response.body).to include('O seu acesso é pessoal.').and include('Li e aceito os termos de uso e a Política de Privacidade.')
      post '/cliente/termos', params: { aceite: '1' }
      expect(response).to redirect_to('/cliente/boas-vindas')
      get '/cliente/boas-vindas'
      expect(response.body).to include('Seu caso na palma da mão').and include('1 de 3').and include('Pular')
      get '/cliente/boas-vindas', params: { passo: 3 }
      expect(response.body).to include('Assine e fale com a equipe').and include('Começar')
    end

    it 'tela do processo mostra a linha do tempo por fases' do
      entrar
      get '/cliente/processos/1'
      expect(response.body).to include('Pedido no INSS').and include('aria-current="step"').and include('Perícia marcada')
      expect(response.body).not_to include('>Recurso<')
    end
  end

  it 'sem a chave v2: sem boas-vindas e sem linha do tempo por fases' do
    entrar
    get '/cliente/boas-vindas'
    expect(response).to redirect_to('/cliente/inicio')
    get '/cliente/processos/1'
    expect(response.body).not_to include('Pedido no INSS')
  end

  it 'registra data/hora + IP no login e no 1º acesso do dia (Marco Civil)' do
    entrar
    get '/cliente/inicio'
    expect(cliente.acessos.count).to eq 2
    expect(cliente.acessos.last.ip).to be_present
  end

  it 'com os textos v2, pergunta da IA aparece até o cliente responder' do
    with_modified_env PORTAL_TEXTOS_V2: 'on' do
      entrar
      get '/cliente/inicio'
      expect(response.body).to include('Uma pergunta rápida')
      post '/cliente/ia', params: { ia: 'nao' }
      expect(cliente.reload.ia_consentimento).to be false
      get '/cliente/inicio'
      expect(response.body).not_to include('Uma pergunta rápida')
    end
  end

  it 'conta dias distintos de acesso (mesmo dia não soma de novo)' do
    entrar
    get '/cliente/inicio'
    get '/cliente/processos/1'
    expect(cliente.reload.dias_acesso).to eq 1
    cliente.update!(ultimo_acesso_em: 2.days.ago)
    get '/cliente/inicio'
    expect(cliente.reload.dias_acesso).to eq 2
    expect(cliente.ultimo_acesso_em).to be_within(1.minute).of(Time.current)
  end

  it 'selo Novo no início até o cliente abrir o processo; etapa interna mostra a exibida' do
    novidade = { 'tipo' => 'etapa', 'titulo' => 'Perícia agendada', 'vista' => false, 'avisada' => true }
    cliente.update!(processos: [processos.first.merge('etapa' => 'NEGADO / AVISAR CLIENTE', 'etapa_cliente' => 'PERICIA AGENDADA',
                                                      'novidades' => [novidade])])
    entrar
    get '/cliente/inicio'
    expect(response.body).to include('class="badge badge-novo"').and include('Perícia agendada')
    expect(response.body).not_to include('Pedido não foi aceito')
    get '/cliente/processos/1'
    expect(cliente.reload.processos.first['novidades'].first['vista']).to be true
    get '/cliente/inicio'
    expect(response.body).not_to include('class="badge badge-novo"')
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

  it 'abas Documentos, Equipe e Conta, com o menu e o contador de pendências' do
    entrar
    get '/cliente/documentos'
    expect(response.body).to include('Para enviar').and include('CNIS atualizado').and include('class="menu-badge"')
    get '/cliente/equipe'
    expect(response.body).to include('Chamar no WhatsApp').and include('Ramon Antonio').and include('Rua Coronel Teixeira, 40')
    get '/cliente/conta'
    expect(response.body).to include('Trocar senha').and include('Sair')
    expect(response.body).not_to include(cliente.cpf)
  end

  it 'início: assunto, número e resumo do que falta fazer' do
    entrar
    get '/cliente/inicio'
    expect(response.body).to include('Auxílio-acidente').and include('nº 5003800-40.2022.4.04.7207').and include('Para você fazer')
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

  it 'atualizar não trava o cliente quando o ADVBOX está fora do ar' do
    allow(Ramon::PortalSyncService).to receive(:new).and_raise(Ramon::AdvboxClient::UnavailableError)
    entrar
    post '/cliente/atualizar'
    expect(cliente.reload.atualizacao_pedida_em).to be_nil
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

    it 'fluxo "Documento enviado pelo Painel" no comando: o código não enfileira; o fluxo pede o mesmo job' do
      entrar
      with_modified_env(RAMON_FLUXO_DOCUMENTO_PAINEL: 'on') do
        Ramon::Fluxos::Migracao.semear(account, 'documento_painel')
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'documento_painel', 'normal')
        expect { post '/cliente/processos/1/envios', params: { file: pdf, item: 'CNIS atualizado', post_id: 9 } }
          .not_to have_enqueued_job(Ramon::PortalEnvioJob)
      end
      envio = PortalEnvio.last
      expect { perform_enqueued_jobs(only: Ramon::FluxoAvancarJob) }.to have_enqueued_job(Ramon::PortalEnvioJob).with(envio.id)
      expect(response).to redirect_to('/cliente/processos/1')
    end
  end

  describe 'Seus documentos (só o que o cliente assinou ou enviou)' do
    let(:pdf) { fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') }

    it 'baixa o próprio envio; envio de outro cliente dá 404' do
      meu = create(:portal_envio, portal_cliente: cliente, arquivo: pdf)
      alheio = create(:portal_envio, portal_cliente: create(:portal_cliente, account: account), arquivo: pdf)
      entrar
      get '/cliente/documentos'
      expect(response.body).to include('Seus documentos').and include('Já com o escritório')
      get "/cliente/envios/#{meu.id}/arquivo"
      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Disposition']).to include('attachment')
      get "/cliente/envios/#{alheio.id}/arquivo"
      expect(response).to have_http_status(:not_found)
    end

    it 'contrato assinado redireciona pro arquivo assinado do ZapSign; pendente dá 404' do
      assinada = create(:portal_assinatura, portal_cliente: cliente, status: 'signed', assinado_em: 1.day.ago)
      pendente = create(:portal_assinatura, portal_cliente: cliente)
      allow(Ramon::ZapsignClient).to receive(:doc).with(assinada.doc_token).and_return({ 'signed_file' => 'https://zapsign.s3/assinado.pdf' })
      entrar
      get "/cliente/assinaturas/#{assinada.id}/baixar"
      expect(response).to redirect_to('https://zapsign.s3/assinado.pdf')
      get "/cliente/assinaturas/#{pendente.id}/baixar"
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'tela de assinatura embute o widget do ZapSign do próprio cliente' do
    a = create(:portal_assinatura, portal_cliente: cliente, signer_token: 'sig-1')
    entrar
    get "/cliente/assinaturas/#{a.id}"
    expect(response.body).to include('https://app.zapsign.com.br/verificar/sig-1')
    outro = create(:portal_assinatura)
    get "/cliente/assinaturas/#{outro.id}"
    expect(response).to have_http_status(:not_found)
  end
end
