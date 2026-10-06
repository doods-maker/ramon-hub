require 'rails_helper'

RSpec.describe 'Ramon Conteudo API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:peca) { create(:peca, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/ramon_conteudo" }

  it 'agente não acessa' do
    get base, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lista as peças (sem reprovadas)' do
    create(:peca, account: account, status: 'reprovado')
    get base, headers: admin.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq [peca.id]
  end

  it 'aprova a pauta' do
    post "#{base}/#{peca.id}/aprovar", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(peca.reload.status).to eq 'aprovado'
  end

  it 'reprova com nota' do
    post "#{base}/#{peca.id}/reprovar", params: { nota: 'tema repetido' }, headers: admin.create_new_auth_token
    expect(peca.reload).to have_attributes(status: 'reprovado', nota_reprovacao: 'tema repetido')
  end

  it '409 quando o status mudou por baixo' do
    peca.update_columns(status: 'montando') # rubocop:disable Rails/SkipsModelValidations
    post "#{base}/#{peca.id}/aprovar", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:conflict)
    expect(peca.reload.status).to eq 'montando'
  end

  it 'edita a legenda de peça pronta' do
    peca.update_columns(status: 'montado') # rubocop:disable Rails/SkipsModelValidations
    patch "#{base}/#{peca.id}/atualizar_legenda", params: { legenda: 'nova' }, headers: admin.create_new_auth_token
    expect(peca.reload.legenda).to eq 'nova'
  end

  it 'não edita legenda de peça publicada' do
    peca.update_columns(status: 'publicado') # rubocop:disable Rails/SkipsModelValidations
    patch "#{base}/#{peca.id}/atualizar_legenda", params: { legenda: 'nova' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:conflict)
  end

  it 'pede refação dos cards escolhidos' do
    peca.update_columns(status: 'montado') # rubocop:disable Rails/SkipsModelValidations
    post "#{base}/#{peca.id}/refazer", params: { cards: [2, 9, 'x'] }, headers: admin.create_new_auth_token
    expect(peca.reload).to have_attributes(status: 'montado', refazer_cards: [2])
  end

  describe 'agenda' do
    before { peca.update_columns(status: 'montado', imagens: ['u1']) } # rubocop:disable Rails/SkipsModelValidations

    it 'detalhe traz a sugestão da grade' do
      get "#{base}/#{peca.id}", headers: admin.create_new_auth_token
      expect(response.parsed_body['sugestao_horario']).to be_present
    end

    it 'agenda pro futuro' do
      quando = 2.days.from_now.change(usec: 0)
      post "#{base}/#{peca.id}/agendar", params: { agendado_para: quando.iso8601 }, headers: admin.create_new_auth_token
      expect(peca.reload).to have_attributes(status: 'agendado', agendado_para: quando)
    end

    it 'recusa agendar com imagem sendo refeita' do
      peca.update_columns(refazer_cards: [2]) # rubocop:disable Rails/SkipsModelValidations
      post "#{base}/#{peca.id}/agendar", params: { agendado_para: 2.days.from_now.iso8601 }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:conflict)
      expect(peca.reload.status).to eq 'montado'
    end

    it 'recusa horário no passado' do
      post "#{base}/#{peca.id}/agendar", params: { agendado_para: 1.hour.ago.iso8601 }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(peca.reload.status).to eq 'montado'
    end

    it 'publicar agora agenda pra já e dispara o job' do
      expect { post "#{base}/#{peca.id}/publicar_agora", headers: admin.create_new_auth_token }
        .to have_enqueued_job(Ramon::PublicarPecasJob)
      expect(peca.reload.status).to eq 'agendado'
    end

    it 'cancela agendamento' do
      peca.update_columns(status: 'agendado', agendado_para: 1.day.from_now) # rubocop:disable Rails/SkipsModelValidations
      post "#{base}/#{peca.id}/cancelar_agendamento", headers: admin.create_new_auth_token
      expect(peca.reload).to have_attributes(status: 'montado', agendado_para: nil)
    end

    it 'falha ambígua só tenta de novo com a conferência marcada', :aggregate_failures do
      erro = 'Pode ter ido ao ar — conferir no Instagram antes de tentar de novo. (timeout)'
      peca.update_columns(status: 'falhou', erro: erro) # rubocop:disable Rails/SkipsModelValidations
      get base, headers: admin.create_new_auth_token
      expect(response.parsed_body['payload'].first['ambigua']).to be(true)

      post "#{base}/#{peca.id}/tentar_de_novo", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(peca.reload.status).to eq 'falhou'

      post "#{base}/#{peca.id}/tentar_de_novo", params: { conferido: true }, headers: admin.create_new_auth_token
      expect(peca.reload.status).to eq 'agendado'
    end

    it 'falha comum tenta de novo sem conferência' do
      peca.update_columns(status: 'falhou', erro: 'Contêiner p1: ERROR') # rubocop:disable Rails/SkipsModelValidations
      post "#{base}/#{peca.id}/tentar_de_novo", headers: admin.create_new_auth_token
      expect(peca.reload.status).to eq 'agendado'
    end

    it 'tentar de novo recusa peça que já tem id na Meta' do
      peca.update_columns(status: 'falhou', ig_media_id: 'm1') # rubocop:disable Rails/SkipsModelValidations
      post "#{base}/#{peca.id}/tentar_de_novo", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:conflict)
    end
  end
end
