require 'rails_helper'

RSpec.describe 'Abrir no Drive a peça da esteira', type: :request do
  let(:account) { create(:account) }
  let(:eduardo) { create(:user, account: account, role: :administrator, email: 'eduardo@example.com') }
  let(:intruso) { create(:user, account: account, role: :administrator, email: 'intruso@example.com') }
  let(:link) { 'https://docs.google.com/document/d/abc/edit' }

  def abrir(nome, quem: eduardo)
    get '/ramon_painel_agentes/peca', params: { nome: nome },
                                      headers: { 'Cookie' => "cw_d_session_info=#{CGI.escape(quem.create_new_auth_token.to_json)}" }
  end

  around { |exemplo| with_modified_env(RAMON_PAINEL_AGENTES_EMAILS: 'eduardo@example.com') { exemplo.run } }

  before { allow(Ramon::DriveClient).to receive(:configured?).and_return(true) }

  it 'quem vê o painel vai direto para o arquivo no Drive' do
    allow(Ramon::DriveClient).to receive(:peca_na_raiz).with('Petição inicial — Fulano Ficticio.docx').and_return(link)
    abrir('Petição inicial — Fulano Ficticio.docx')
    expect(response).to redirect_to(link)
  end

  it 'barra quem não vê o painel, sem tocar no Drive' do
    allow(Ramon::DriveClient).to receive(:peca_na_raiz)
    abrir('Peça.docx', quem: intruso)
    expect(response).to have_http_status(:unauthorized)
    expect(Ramon::DriveClient).not_to have_received(:peca_na_raiz)
  end

  it 'recusa o que não é nome de .docx (sem pasta), sem tocar no Drive' do
    allow(Ramon::DriveClient).to receive(:peca_na_raiz)
    ['', 'peca.pdf', '../x.docx', 'a/b.docx', 'a\\b.docx', "#{'x' * 201}.docx"].each do |nome|
      abrir(nome)
      expect(response).to have_http_status(:bad_request), nome
    end
    expect(Ramon::DriveClient).not_to have_received(:peca_na_raiz)
  end

  it 'peça não achada, ou link que não é https do Google: 404 com aviso' do
    allow(Ramon::DriveClient).to receive(:peca_na_raiz).and_return(nil, 'https://malicioso.example.com/x', 'http://docs.google.com/x')
    3.times do
      abrir('Peça.docx')
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('não encontrada')
    end
  end

  it 'Drive do hub desligado: 404 dizendo isso, sem buscar' do
    allow(Ramon::DriveClient).to receive(:configured?).and_return(false)
    allow(Ramon::DriveClient).to receive(:peca_na_raiz)
    abrir('Peça.docx')
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include('não está conectado')
    expect(Ramon::DriveClient).not_to have_received(:peca_na_raiz)
  end

  it 'Drive fora do ar: 502 com aviso' do
    allow(Ramon::DriveClient).to receive(:peca_na_raiz).and_raise(Google::Apis::ServerError.new('fora'))
    abrir('Peça.docx')
    expect(response).to have_http_status(:bad_gateway)
  end
end
