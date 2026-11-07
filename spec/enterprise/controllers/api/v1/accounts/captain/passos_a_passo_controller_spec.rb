require 'rails_helper'

# Tela de upload das imagens do passo a passo (Inteligência › Assistentes › assistente): uma por tema, só administrador e só
# no assistente ligado a uma etapa conduzida (o "Documentos").
RSpec.describe 'Api::V1::Accounts::Captain::PassosAPasso', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}/passos_a_passo" }
  let(:png) { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

  before { Ramon::EtapasPosVenda.criar!(account).first.update!(captain_assistant: assistant) }

  def tema(nome) = response.parsed_body['temas'].find { |t| t['tema'] == nome }

  it 'agente não vê nem sobe imagem' do
    get url, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'admin sobe a imagem do tema (o nome vira o tema), troca sem duplicar e remove', :aggregate_failures do
    2.times { post url, headers: admin.create_new_auth_token, params: { tema: 'meu_inss_cnis', file: png } }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['ligado']).to be(true)
    expect(tema('meu_inss_cnis')).to include('nome' => 'meu_inss_cnis.png', 'url' => be_present)
    expect(assistant.reload.passos_a_passo.count).to eq(1)

    delete "#{url}/meu_inss_cnis", headers: admin.create_new_auth_token, as: :json
    expect(tema('meu_inss_cnis')).to include('url' => nil)
  end

  it 'recusa tema fora da lista e arquivo que não é JPG ou PNG de verdade, com o motivo', :aggregate_failures do
    post url, headers: admin.create_new_auth_token, params: { tema: 'xablau', file: png }
    expect(response).to have_http_status(:unprocessable_entity)

    pdf_dizendo_png = fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'image/png')
    post url, headers: admin.create_new_auth_token, params: { tema: 'meu_inss_cnis', file: pdf_dizendo_png }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('JPG ou PNG')
  end

  it 'assistente que não é o de uma etapa conduzida: sem a seção e sem upload', :aggregate_failures do
    outro = create(:captain_assistant, account: account)
    outra_url = "/api/v1/accounts/#{account.id}/captain/assistants/#{outro.id}/passos_a_passo"

    get outra_url, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['ligado']).to be(false)

    post outra_url, headers: admin.create_new_auth_token, params: { tema: 'meu_inss_cnis', file: png }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(outro.reload.passos_a_passo).to be_empty
  end
end
