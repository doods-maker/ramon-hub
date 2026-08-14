require 'rails_helper'

RSpec.describe 'Ramon Prescription Radar API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/ramon_prescription_radar" }
  let(:active_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }
  let(:lost_stage) { account.lead_stages.find_by(is_lost: true) }

  it 'ordena por sangramento e soma o resumo (incluindo lead perdido)' do
    big = create(:lead, account: account, lead_stage: lost_stage, dcb_em: 70.months.ago.to_date, benefit_monthly_value: 2000)
    small = create(:lead, account: account, lead_stage: active_stage, dcb_em: 65.months.ago.to_date, benefit_monthly_value: 1000)
    risk = create(:lead, account: account, lead_stage: active_stage, dcb_em: 58.months.ago.to_date, benefit_monthly_value: 500)

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['items'].pluck('lead_id')).to eq([big.id, small.id, risk.id])
    expect(body['items'].first).to include('is_lost' => true, 'lost_installments' => 10, 'monthly_value' => 2000.0)
    expect(body['summary']).to include('bleeding_monthly' => 3000.0, 'bleeding_count' => 2)
    expect(body['summary']).to include('at_risk_90d_monthly' => 500.0, 'at_risk_90d_count' => 1)
  end

  it 'exclui ganhos, caso de cálculo, sem DCB e quem consumiu menos da metade do prazo' do
    won_stage = account.lead_stages.find_by(is_won: true)
    create(:lead, account: account, lead_stage: won_stage, dcb_em: 70.months.ago.to_date, benefit_monthly_value: 900)
    create(:lead, account: account, lead_stage: active_stage, dcb_em: 70.months.ago.to_date, source: Lead::FONTE_CALCULO)
    create(:lead, account: account, lead_stage: active_stage, dcb_em: 10.months.ago.to_date)
    create(:lead, account: account, lead_stage: active_stage)
    kept = create(:lead, account: account, lead_stage: active_stage, dcb_em: 40.months.ago.to_date)

    get url, headers: agent.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['items'].pluck('lead_id')).to eq([kept.id])
    expect(body['items'].first['months_to_cliff']).to eq(20)
    expect(body['items'].first['pct_consumed']).to be_within(0.01).of(0.66)
    expect(body['summary']).to include('bleeding_count' => 0, 'at_risk_90d_count' => 0)
  end

  it 'expõe o consent_marketing do contato (critério do guard de campanha)' do
    contact = create(:contact, account: account, custom_attributes: { 'consent_marketing' => { 'granted' => true } })
    create(:lead, account: account, lead_stage: active_stage, contact: contact, dcb_em: 62.months.ago.to_date, benefit_monthly_value: 800)
    create(:lead, account: account, lead_stage: active_stage, dcb_em: 61.months.ago.to_date)

    get url, headers: agent.create_new_auth_token, as: :json

    consents = response.parsed_body['items'].to_h { |item| [item['lead_id'], item['consent_marketing']] }
    expect(consents.values).to contain_exactly(true, false)
  end

  describe 'Ramon Pos Venda API' do
    let(:url) { "/api/v1/accounts/#{account.id}/ramon_pos_venda" }
    let(:won_stage) { account.lead_stages.find_by(is_won: true) }

    it 'separa ganhos com doc pendente dos concluidos, e ganho sem item de documento na tese fica fora' do
      thesis = create(:thesis, account: account)
      doc_item = create(:thesis_item, thesis: thesis, section: 'documento')

      pendente = create(:lead, account: account, lead_stage: won_stage, thesis: thesis)
      concluido = create(:lead, account: account, lead_stage: won_stage, thesis: thesis,
                                custom_attributes: { 'doc_status' => { doc_item.id.to_s => 'recebido' } })

      thesis_sem_documento = create(:thesis, account: account)
      create(:thesis_item, thesis: thesis_sem_documento, section: 'colheita')
      fora = create(:lead, account: account, lead_stage: won_stage, thesis: thesis_sem_documento)

      get url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['pendentes'].pluck('id')).to eq([pendente.id])
      expect(body['pendentes'].first).to include('docs_received' => 0, 'docs_total' => 1)
      expect(body['concluidos'].pluck('id')).to eq([concluido.id])
      expect((body['pendentes'] + body['concluidos']).pluck('id')).not_to include(fora.id)
    end
  end
end
