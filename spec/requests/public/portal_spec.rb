require 'rails_helper'

RSpec.describe 'Portal do cliente (link mágico)', type: :request do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account, name: 'Maria de Lourdes') }

  describe 'GET /portal/:token' do
    it 'renderiza a página com token válido, com nome e rodapé de compliance' do
      get "/portal/#{lead.ensure_portal_token!}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Olá, Maria')
      expect(response.body).to include('Conteúdo informativo sobre o andamento do seu atendimento.')
    end

    it 'mostra a etapa atual na timeline com a pill "agora"' do
      get "/portal/#{lead.ensure_portal_token!}"

      expect(response.body).to include(lead.lead_stage.name)
      expect(response.body).to include('agora')
    end

    it 'token inválido devolve 404 com página neutra' do
      get '/portal/token-que-nao-existe'

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('Este link não está mais disponível')
    end

    it 'lead perdido mostra estado neutro sem expor a perda' do
      perdido = account.lead_stages.find_by!(is_lost: true)
      lead.update!(lead_stage: perdido, lost_reason: 'sem retorno')

      get "/portal/#{lead.ensure_portal_token!}"

      expect(response.body).to include('em análise')
      expect(response.body).not_to include(perdido.name)
      expect(response.body).not_to include('sem retorno')
    end

    it 'lista os documentos pendentes da tese no card de pendência' do
      thesis = create(:thesis, account: account)
      create(:thesis_item, thesis: thesis, section: 'documento', title: 'Comprovante de residência')
      lead.update!(thesis: thesis)

      get "/portal/#{lead.ensure_portal_token!}"

      expect(response.body).to include('Falta 1 documento')
      expect(response.body).to include('Comprovante de residência')
    end
  end

  describe 'POST /portal/:token/upload' do
    let(:conversation) { create(:conversation, account: account) }
    let(:file) { fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') }

    before { lead.update!(conversation: conversation, contact: conversation.contact) }

    it 'cria mensagem incoming na conversa do lead com o anexo' do
      expect do
        post "/portal/#{lead.ensure_portal_token!}/upload", params: { file: file }
      end.to change(conversation.messages, :count).by(1)

      message = conversation.messages.reorder(:id).last
      expect(message.message_type).to eq('incoming')
      expect(message.sender).to eq(conversation.contact)
      expect(message.attachments.count).to eq(1)
      expect(response).to redirect_to("/portal/#{lead.portal_token}")
    end

    it 'recusa content-type fora da lista sem criar mensagem' do
      bad = fixture_file_upload(Rails.root.join('spec/assets/sample.mp3'), 'audio/mpeg')

      expect do
        post "/portal/#{lead.ensure_portal_token!}/upload", params: { file: bad }
      end.not_to change(Message, :count)
      expect(response).to redirect_to("/portal/#{lead.portal_token}")
    end

    it 'token inválido devolve 404 sem criar nada' do
      expect do
        post '/portal/token-invalido/upload', params: { file: file }
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:not_found)
    end
  end
end
