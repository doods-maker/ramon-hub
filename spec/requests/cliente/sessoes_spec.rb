require 'rails_helper'

RSpec.describe 'Painel do cliente — sessões', type: :request do
  let(:account) { create(:account) }
  let!(:cliente) { create(:portal_cliente, account: account, email: 'maria@exemplo.com', convidado_em: 1.day.ago) }

  it 'GET /cliente mostra o formulário de e-mail' do
    get '/cliente'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Seu e-mail')
  end

  it 'e-mail desconhecido recebe a mesma tela neutra e não manda e-mail' do
    expect { post '/cliente/codigo', params: { email: 'ninguem@exemplo.com' } }
      .not_to have_enqueued_mail(Ramon::PortalMailer, :codigo)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Se este e-mail estiver cadastrado')
  end

  it 'e-mail conhecido gera código e enfileira o e-mail' do
    expect { post '/cliente/codigo', params: { email: ' Maria@Exemplo.com ' } }
      .to have_enqueued_mail(Ramon::PortalMailer, :codigo)
    expect(cliente.reload.codigo_digest).to be_present
  end

  it 'código certo entra, consome o código e redireciona pro início' do
    codigo = cliente.gerar_codigo!
    post '/cliente/entrar', params: { email: 'maria@exemplo.com', codigo: codigo }
    expect(response).to redirect_to('/cliente/inicio')
    expect(cliente.reload.codigo_digest).to be_nil
    get '/cliente/inicio'
    expect(response).to have_http_status(:ok)
  end

  it 'código errado devolve 422 sem sessão' do
    cliente.gerar_codigo!
    post '/cliente/entrar', params: { email: 'maria@exemplo.com', codigo: '000000' }
    expect(response).to have_http_status(:unprocessable_entity)
    get '/cliente/inicio'
    expect(response).to redirect_to('/cliente')
  end

  it 'sair apaga a sessão' do
    post '/cliente/entrar', params: { email: 'maria@exemplo.com', codigo: cliente.gerar_codigo! }
    delete '/cliente/sair'
    get '/cliente/inicio'
    expect(response).to redirect_to('/cliente')
  end
end
