require 'rails_helper'

RSpec.describe 'Painel do cliente — sessões', type: :request do
  let(:account) { create(:account) }
  let!(:cliente) { create(:portal_cliente, account: account, cpf: '12345678901', email: 'maria@exemplo.com', convidado_em: 1.day.ago) }
  let!(:senha) { cliente.gerar_senha_provisoria! }

  it 'GET /cliente mostra o formulário de CPF e senha' do
    get '/cliente'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Seu CPF').and include('Sua senha').and include('Esqueci a senha')
  end

  it 'CPF (com pontuação) + senha provisória entra e redireciona pro início' do
    post '/cliente/entrar', params: { cpf: '123.456.789-01', senha: senha }
    expect(response).to redirect_to('/cliente/inicio')
    get '/cliente/inicio'
    expect(response).to have_http_status(:ok)
  end

  it 'senha errada ou CPF desconhecido devolvem a mesma mensagem, 422, sem sessão' do
    post '/cliente/entrar', params: { cpf: '12345678901', senha: '000000' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('CPF ou senha não conferem')
    post '/cliente/entrar', params: { cpf: '99999999999', senha: senha }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('CPF ou senha não conferem')
    get '/cliente/inicio'
    expect(response).to redirect_to('/cliente')
  end

  it 'cliente ainda não convidado não entra' do
    cliente.update!(convidado_em: nil)
    post '/cliente/entrar', params: { cpf: '12345678901', senha: senha }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'esqueci a senha: CPF com e-mail gera código e enfileira o e-mail' do
    expect { post '/cliente/codigo', params: { cpf: '123.456.789-01' } }
      .to have_enqueued_mail(Ramon::PortalMailer, :codigo)
    expect(cliente.reload.codigo_digest).to be_present
    expect(response.body).to include('Digite o código')
  end

  it 'esqueci a senha: CPF sem e-mail ou desconhecido recebe a mesma tela neutra e não manda e-mail' do
    cliente.update!(email: nil)
    expect { post '/cliente/codigo', params: { cpf: '12345678901' } }
      .not_to have_enqueued_mail(Ramon::PortalMailer, :codigo)
    expect(response.body).to include('Se houver um e-mail cadastrado')
    expect { post '/cliente/codigo', params: { cpf: '99999999999' } }
      .not_to have_enqueued_mail(Ramon::PortalMailer, :codigo)
    expect(response.body).to include('Se houver um e-mail cadastrado')
  end

  it 'código certo entra, consome o código e leva pra escolher senha nova' do
    codigo = cliente.gerar_codigo!
    post '/cliente/entrar-codigo', params: { cpf: '12345678901', codigo: codigo }
    expect(response).to redirect_to('/cliente/senha/edit')
    expect(cliente.reload.codigo_digest).to be_nil
    get '/cliente/senha/edit'
    expect(response).to have_http_status(:ok)
  end

  it 'código errado devolve 422 sem sessão' do
    cliente.gerar_codigo!
    post '/cliente/entrar-codigo', params: { cpf: '12345678901', codigo: '000000' }
    expect(response).to have_http_status(:unprocessable_entity)
    get '/cliente/inicio'
    expect(response).to redirect_to('/cliente')
  end

  it 'trocar senha exige confirmação igual e regra de 6 números; a nova passa a valer' do
    post '/cliente/entrar', params: { cpf: '12345678901', senha: senha }
    patch '/cliente/senha', params: { senha: '654321', confirmacao: '111111' }
    expect(response).to have_http_status(:unprocessable_entity)
    patch '/cliente/senha', params: { senha: '12a45', confirmacao: '12a45' }
    expect(response).to have_http_status(:unprocessable_entity)
    patch '/cliente/senha', params: { senha: '654321', confirmacao: '654321' }
    expect(response).to redirect_to('/cliente/inicio')
    expect(cliente.reload.authenticate_senha('654321')).to be_truthy
    expect(cliente.authenticate_senha(senha)).to be false
  end

  it 'trocar senha sem sessão redireciona pro login' do
    get '/cliente/senha/edit'
    expect(response).to redirect_to('/cliente')
  end

  it 'sair apaga a sessão' do
    post '/cliente/entrar', params: { cpf: '12345678901', senha: senha }
    delete '/cliente/sair'
    get '/cliente/inicio'
    expect(response).to redirect_to('/cliente')
  end
end
