require 'rails_helper'

RSpec.describe 'Leads API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:novo) { account.lead_stages.find_by(name: 'Novo') }
  let(:qualif) { account.lead_stages.find_by(name: 'Qualificação') }
  let(:perdido) { account.lead_stages.find_by(is_lost: true) }

  it 'cria um lead na etapa Novo' do
    post "/api/v1/accounts/#{account.id}/leads",
         params: { name: 'João', lead_stage_id: novo.id },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['name']).to eq('João')
    expect(account.leads.count).to eq(1)
  end

  describe 'dedup por telefone na criação manual (contato já resolvido pelo front)' do
    let(:contact) { create(:contact, account: account, phone_number: '+5548999887766') }

    it 'devolve 409 com o lead ABERTO existente do mesmo contato, sem criar' do
      existing = create(:lead, account: account, lead_stage: novo, contact: contact, name: 'Ana')
      expect do
        post "/api/v1/accounts/#{account.id}/leads",
             params: { name: 'Ana de novo', lead_stage_id: novo.id, contact_id: contact.id },
             headers: admin.create_new_auth_token, as: :json
      end.not_to change(account.leads, :count)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('DUPLICATE_LEAD')
      expect(response.parsed_body['existing']['id']).to eq(existing.id)
      expect(response.parsed_body['existing']['stage_name']).to eq('Novo')
    end

    it 'force cria mesmo assim, apesar do lead aberto existente' do
      create(:lead, account: account, lead_stage: novo, contact: contact)
      expect do
        post "/api/v1/accounts/#{account.id}/leads",
             params: { name: 'Ana de novo', lead_stage_id: novo.id, contact_id: contact.id, force: true },
             headers: admin.create_new_auth_token, as: :json
      end.to change(account.leads, :count).by(1)
      expect(response).to have_http_status(:success)
    end

    it 'lead fechado (perdido) do contato não bloqueia a criação' do
      create(:lead, account: account, lead_stage: perdido, contact: contact, lost_reason: 'x')
      expect do
        post "/api/v1/accounts/#{account.id}/leads",
             params: { name: 'Ana volta', lead_stage_id: novo.id, contact_id: contact.id },
             headers: admin.create_new_auth_token, as: :json
      end.to change(account.leads, :count).by(1)
      expect(response).to have_http_status(:success)
    end
  end

  it 'move um lead de etapa via update' do
    lead = create(:lead, account: account, lead_stage: novo, name: 'Ana')
    patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
          params: { lead_stage_id: qualif.id, position: 1.5 },
          headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(lead.reload.lead_stage).to eq(qualif)
    expect(lead.position).to eq(1.5)
  end

  it 'lista os leads da conta' do
    create(:lead, account: account, lead_stage: novo)
    get "/api/v1/accounts/#{account.id}/leads",
        headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['payload'].size).to eq(1)
  end

  describe 'caso de cálculo (source calculo-advbox)' do
    let(:contact) { create(:contact, account: account) }
    let!(:caso) do
      create(:lead, account: account, lead_stage: novo, contact: contact, source: Lead::FONTE_CALCULO)
    end

    it 'não aparece no board (sem contact_id)' do
      get "/api/v1/accounts/#{account.id}/leads",
          headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('id')).not_to include(caso.id)
    end

    it 'aparece na visão por pessoa (contact_id)' do
      get "/api/v1/accounts/#{account.id}/leads",
          params: { contact_id: contact.id },
          headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['payload'].pluck('id')).to include(caso.id)
    end

    it 'não bloqueia a criação de lead comercial do mesmo contato (dedup ignora)' do
      expect do
        post "/api/v1/accounts/#{account.id}/leads",
             params: { name: 'Lead real', lead_stage_id: novo.id, contact_id: contact.id },
             headers: admin.create_new_auth_token, as: :json
      end.to change(account.leads.reorder(nil), :count).by(1)
      expect(response).to have_http_status(:success)
    end
  end

  it 'serializa value/source + nomes desnormalizados + contato', :aggregate_failures do
    contact = create(:contact, account: account, name: 'Cliente X',
                               phone_number: '+5547999990000', email: 'x@cli.com')
    bt = account.benefit_types.find_by(name: 'Auxílio-acidente')
    lead = create(:lead, account: account, lead_stage: novo, contact: contact,
                         benefit_type: bt, value: 12_000.50, source: 'Meta Ads')
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
        headers: admin.create_new_auth_token, as: :json
    body = response.parsed_body
    expect(body['value'].to_f).to eq(12_000.50)
    expect(body['source']).to eq('Meta Ads')
    expect(body['stage_name']).to eq('Novo')
    expect(body['stage_color']).to eq('#6b7280')
    expect(body['benefit_type_name']).to eq('Auxílio-acidente')
    expect(body['contact_name']).to eq('Cliente X')
    expect(body['contact_phone']).to eq('+5547999990000')
    expect(body['contact_email']).to eq('x@cli.com')
  end

  it 'show expõe cnis_resumo pra pagina Calculos reconhecer CNIS a frio', :aggregate_failures do
    lead = create(:lead, account: account, lead_stage: novo,
                         cnis: { 'filename' => 'cnis.pdf', 'vinculos' => [{ 'seq' => 1 }],
                                 'entrada' => { 'competencias' => [{ 'ano' => 2020, 'mes' => 1 }] } })
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
        headers: admin.create_new_auth_token, as: :json
    resumo = response.parsed_body['cnis_resumo']
    expect(resumo).to be_present
    expect(resumo['filename']).to eq('cnis.pdf')
    expect(resumo['vinculos']).to eq(1)
  end

  it 'show devolve cnis_resumo nulo quando o lead nao tem CNIS' do
    lead = create(:lead, account: account, lead_stage: novo)
    get "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
        headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['cnis_resumo']).to be_nil
  end

  it 'update aceita value/source' do
    lead = create(:lead, account: account, lead_stage: novo)
    patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
          params: { value: 8500.25, source: 'Meta Ads' },
          headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    lead.reload
    expect(lead.value).to eq(8500.25)
    expect(lead.source).to eq('Meta Ads')
  end

  it 'updates dcb_em and benefit_monthly_value' do
    lead = create(:lead, account: account, lead_stage: novo)
    patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
          params: { dcb_em: '2020-01-15', benefit_monthly_value: 800 },
          headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(lead.reload.dcb_em).to eq(Date.new(2020, 1, 15))
    expect(lead.benefit_monthly_value).to eq(BigDecimal(800))
  end

  describe 'POST /api/v1/accounts/{account}/leads/for_conversation' do
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }

    it 'creates a lead in the default stage when none exists' do
      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: conversation.display_id },
             headers: admin.create_new_auth_token, as: :json
      end.to change(account.leads, :count).by(1)
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['conversation_id']).to eq(conversation.id)
      expect(body['stage_name']).to be_present
    end

    it 'returns the existing lead without creating a duplicate' do
      existing = account.leads.create!(conversation: conversation, contact: contact,
                                       lead_stage: account.lead_stages.order(:position).first,
                                       name: 'X')
      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: conversation.display_id },
             headers: admin.create_new_auth_token, as: :json
      end.not_to(change(account.leads, :count))
      expect(response.parsed_body['id']).to eq(existing.id)
    end

    it 'dedupes by contact when the same contact has a lead on a different conversation' do
      existing = account.leads.create!(conversation: conversation, contact: contact,
                                       lead_stage: account.lead_stages.order(:position).first,
                                       name: 'X')
      new_conversation = create(:conversation, account: account, contact: contact)

      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: new_conversation.display_id },
             headers: admin.create_new_auth_token, as: :json
      end.not_to(change(account.leads, :count))

      expect(response.parsed_body['id']).to eq(existing.id)
      expect(existing.reload.conversation_id).to eq(new_conversation.id)
    end

    it 'readonly: devolve o lead existente sem adotar a conversa' do
      other_conversation = create(:conversation, account: account, contact: contact)
      existing = account.leads.create!(conversation: other_conversation, contact: contact,
                                       lead_stage: account.lead_stages.order(:position).first,
                                       name: 'X')
      post "/api/v1/accounts/#{account.id}/leads/for_conversation",
           params: { conversation_id: conversation.display_id, readonly: true },
           headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['id']).to eq(existing.id)
      expect(existing.reload.conversation_id).to eq(other_conversation.id)
    end

    it 'readonly: 204 sem criar lead quando a conversa não tem funil' do
      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: conversation.display_id, readonly: true },
             headers: admin.create_new_auth_token, as: :json
      end.not_to(change(account.leads, :count))
      expect(response).to have_http_status(:no_content)
    end

    it 'cria lead novo no for_conversation quando os leads do contato estão fechados' do
      lost_stage = account.lead_stages.find_by(is_lost: true)
      contact = create(:contact, account: account)
      create(:lead, account: account, contact: contact, lead_stage: lost_stage, lost_reason: 'sem viabilidade')
      conversation = create(:conversation, account: account, contact: contact)

      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: conversation.display_id },
             headers: admin.create_new_auth_token
      end.to change { account.leads.count }.by(1)
    end

    it 'resolve a conversa pelo display_id, não pela PK global' do
      create(:conversation) # noutra conta: desloca a PK global da tabela
      conversation = create(:conversation, account: account, contact: contact)
      expect(conversation.id).not_to eq(conversation.display_id)

      post "/api/v1/accounts/#{account.id}/leads/for_conversation",
           params: { conversation_id: conversation.display_id },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['conversation_id']).to eq(conversation.id)
    end
  end

  describe 'GET /api/v1/accounts/{account}/leads (filtros)' do
    let(:bpc_teste) { account.benefit_types.create!(name: 'BPC-teste') }

    def ids(response)
      response.parsed_body['payload'].map { |l| l['id'] }
    end

    it 'sem params retorna todos os leads' do
      a = account.leads.create!(name: 'A', lead_stage: novo)
      b = account.leads.create!(name: 'B', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      expect(ids(response)).to contain_exactly(a.id, b.id)
    end

    it 'index é slim (sem custom_attributes); show traz o jsonb completo' do
      lead = account.leads.create!(name: 'A', lead_stage: novo, custom_attributes: { 'colheita_status' => { 'x' => true } })
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      expect(response.parsed_body['payload'].first).not_to have_key('custom_attributes')
      get "/api/v1/accounts/#{account.id}/leads/#{lead.id}", headers: admin.create_new_auth_token
      expect(response.parsed_body['custom_attributes']).to eq('colheita_status' => { 'x' => true })
    end

    it 'expõe follow_up_count e follow_up_last_at também no índice slim (badge do card)' do
      account.leads.create!(name: 'A', lead_stage: novo,
                            custom_attributes: { 'follow_up' => { 'tentativas' => 2, 'ultima_em' => '2026-07-20T11:00:00Z' } })
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      row = response.parsed_body['payload'].first
      expect(row['follow_up_count']).to eq(2)
      expect(row['follow_up_last_at']).to eq('2026-07-20T11:00:00Z')
      expect(row).not_to have_key('custom_attributes')
    end

    it 'expõe next_task_due_at e next_task_title da tarefa aberta mais próxima no índice slim' do
      lead = account.leads.create!(name: 'A', lead_stage: novo)
      create(:lead_task, account: account, lead: lead, title: 'Depois', due_at: 3.days.from_now)
      create(:lead_task, account: account, lead: lead, title: 'Ligar pós-perícia', due_at: 1.day.from_now)
      create(:lead_task, account: account, lead: lead, title: 'Feita', due_at: 1.hour.from_now, completed_at: Time.current)
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      row = response.parsed_body['payload'].first
      expect(row['next_task_title']).to eq('Ligar pós-perícia')
      expect(Time.zone.parse(row['next_task_due_at'])).to be_within(1.minute).of(1.day.from_now)
    end

    it 'lead sem tarefa aberta expõe next_task_due_at e next_task_title nulos' do
      account.leads.create!(name: 'A', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      row = response.parsed_body['payload'].first
      expect(row['next_task_due_at']).to be_nil
      expect(row['next_task_title']).to be_nil
    end

    it 'expõe o bloco sla calculado da conversa no índice slim' do
      inbox = create(:inbox, account: account, auto_create_lead: true, first_response_sla_minutes: 60)
      conversation = create(:conversation, account: account, inbox: inbox)
      account.leads.create!(name: 'A', lead_stage: novo, conversation_id: conversation.id)
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      sla = response.parsed_body['payload'].first['sla']
      expect(sla['minutes']).to eq(60)
      expect(Time.zone.parse(sla['due_at'])).to be_within(1.minute).of(conversation.created_at + 60.minutes)
      expect(sla['replied_at']).to be_nil
    end

    it 'lead sem conversa ou com inbox sem auto_create_lead expõe sla nulo' do
      inbox = create(:inbox, account: account, auto_create_lead: false, first_response_sla_minutes: 60)
      conversation = create(:conversation, account: account, inbox: inbox)
      account.leads.create!(name: 'Sem conversa', lead_stage: novo)
      account.leads.create!(name: 'Inbox comum', lead_stage: novo, conversation_id: conversation.id)
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      expect(response.parsed_body['payload'].pluck('sla')).to eq([nil, nil])
    end

    it 'lead sem retomadas expõe follow_up_count zero' do
      account.leads.create!(name: 'A', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      expect(response.parsed_body['payload'].first['follow_up_count']).to eq(0)
    end

    it 'expõe docs_received e docs_total também no índice slim (badge do card)' do
      thesis = create(:thesis, account: account)
      doc_item = create(:thesis_item, thesis: thesis, section: 'documento', content: 'RG')
      create(:thesis_item, thesis: thesis, section: 'colheita', content: 'Renda')
      account.leads.create!(name: 'A', lead_stage: novo, thesis: thesis,
                            custom_attributes: { 'doc_status' => { doc_item.id.to_s => 'recebido' } })
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      row = response.parsed_body['payload'].first
      expect(row['docs_received']).to eq(1)
      expect(row['docs_total']).to eq(1)
      expect(row).not_to have_key('custom_attributes')
    end

    it 'lead sem tese expõe docs_received e docs_total zerados' do
      account.leads.create!(name: 'A', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads", headers: admin.create_new_auth_token
      row = response.parsed_body['payload'].first
      expect(row['docs_received']).to eq(0)
      expect(row['docs_total']).to eq(0)
    end

    it 'filtra por source' do
      a = account.leads.create!(name: 'A', lead_stage: novo, source: 'meta-ads')
      account.leads.create!(name: 'B', lead_stage: novo, source: 'indicacao')
      get "/api/v1/accounts/#{account.id}/leads",
          params: { source: 'meta-ads' },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([a.id])
    end

    it 'filtra por channel' do
      a = account.leads.create!(name: 'A', lead_stage: novo, channel: 'meta_ads')
      account.leads.create!(name: 'B', lead_stage: novo, channel: 'indicacao')
      get "/api/v1/accounts/#{account.id}/leads",
          params: { channel: 'meta_ads' },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([a.id])
    end

    it 'filtra por contact_id' do
      contact = create(:contact, account: account)
      a = account.leads.create!(name: 'A', lead_stage: novo, contact: contact)
      account.leads.create!(name: 'B', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { contact_id: contact.id },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([a.id])
    end

    it 'filtra por benefit_type_id' do
      a = account.leads.create!(name: 'A', lead_stage: novo, benefit_type: bpc_teste)
      account.leads.create!(name: 'B', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { benefit_type_id: bpc_teste.id },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([a.id])
    end

    it 'filtra por agent_id casando sdr OU closer' do
      agent = create(:user, account: account, role: :agent)
      as_sdr = account.leads.create!(name: 'S', lead_stage: novo, sdr_id: agent.id)
      as_closer = account.leads.create!(name: 'C', lead_stage: novo, closer_id: agent.id)
      account.leads.create!(name: 'N', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { agent_id: agent.id },
          headers: admin.create_new_auth_token
      expect(ids(response)).to contain_exactly(as_sdr.id, as_closer.id)
    end

    it 'busca q por nome do lead mesmo sem contato' do
      hit = account.leads.create!(name: 'Joana Silva', lead_stage: novo)
      account.leads.create!(name: 'Outro', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { q: 'joana' },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([hit.id])
    end

    it 'filtra por lead_stage_id' do
      a = account.leads.create!(name: 'A', lead_stage: qualif)
      account.leads.create!(name: 'B', lead_stage: novo)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { lead_stage_id: qualif.id },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([a.id])
    end

    it 'filtra por created_after' do
      recente = account.leads.create!(name: 'Recente', lead_stage: novo)
      antigo = account.leads.create!(name: 'Antigo', lead_stage: novo)
      antigo.update_column(:created_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
      get "/api/v1/accounts/#{account.id}/leads",
          params: { created_after: 2.days.ago.to_date.to_s },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([recente.id])
    end

    it 'filtra por stalled numa etapa com stalled_after_days' do
      parado = account.leads.create!(name: 'Parado', lead_stage: qualif)
      parado.update_column(:stage_entered_at, 10.days.ago) # rubocop:disable Rails/SkipsModelValidations
      account.leads.create!(name: 'Fresco', lead_stage: qualif)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { stalled: 'true' },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([parado.id])
    end

    it 'filtra por no_open_task' do
      sem_tarefa = account.leads.create!(name: 'Livre', lead_stage: novo)
      com_tarefa = account.leads.create!(name: 'Ocupado', lead_stage: novo)
      create(:lead_task, account: account, lead: com_tarefa)
      get "/api/v1/accounts/#{account.id}/leads",
          params: { no_open_task: 'true' },
          headers: admin.create_new_auth_token
      expect(ids(response)).to eq([sem_tarefa.id])
    end
  end

  describe 'trava de motivo de perda no update' do
    it 'bloqueia mover para etapa perdida sem motivo com 422', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: novo, name: 'Sem motivo')
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { lead_stage_id: perdido.id },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('LOST_REASON_REQUIRED')
      expect(lead.reload.lead_stage).to eq(novo)
    end

    it 'permite mover para etapa perdida com motivo e grava lost_at', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: novo, name: 'Com motivo')
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { lead_stage_id: perdido.id, lost_reason: 'Honorário' },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      lead.reload
      expect(lead.lead_stage).to eq(perdido)
      expect(lead.lost_at).to be_present
    end

    it 'persiste custom_attributes no update' do
      lead = create(:lead, account: account, lead_stage: novo)
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { custom_attributes: { cpf: '123', origem: 'campanha' } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(lead.reload.custom_attributes).to eq('cpf' => '123', 'origem' => 'campanha')
    end

    it 'update parcial de custom_attributes faz merge — não apaga as demais chaves' do
      lead = create(:lead, account: account, lead_stage: novo,
                           custom_attributes: { 'colheita_status' => { 'a' => true }, 'advbox' => { 'lawsuits_id' => 9 } })
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { custom_attributes: { doc_status: { 'rg' => true } } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(lead.reload.custom_attributes).to eq(
        'colheita_status' => { 'a' => true }, 'advbox' => { 'lawsuits_id' => 9 }, 'doc_status' => { 'rg' => true }
      )
    end
  end

  describe 'valor estimado: flag de origem manual no PATCH' do
    it 'PATCH com value marca origem manual em custom_attributes' do
      lead = create(:lead, account: account, lead_stage: novo)
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { value: 4321 },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(lead.reload.custom_attributes.dig('valor_estimado', 'origem')).to eq('manual')
    end

    it 'PATCH sem value nao cria a flag' do
      lead = create(:lead, account: account, lead_stage: novo)
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { source: 'Meta Ads' },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(lead.reload.custom_attributes).not_to have_key('valor_estimado')
    end

    it 'PATCH com value e custom_attributes junto preserva as duas chaves (deep merge)' do
      lead = create(:lead, account: account, lead_stage: novo,
                           custom_attributes: { 'colheita_status' => { 'a' => true } })
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { value: 999, custom_attributes: { doc_status: { 'rg' => true } } },
            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      attrs = lead.reload.custom_attributes
      expect(attrs.dig('valor_estimado', 'origem')).to eq('manual')
      expect(attrs.dig('doc_status', 'rg')).to be(true)
      expect(attrs.dig('colheita_status', 'a')).to be(true)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/leads/:id/portal_link' do
    it 'gera o token e devolve a URL pública completa; segunda chamada reusa o mesmo token' do
      lead = create(:lead, account: account, lead_stage: novo)
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/portal_link",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      url = response.parsed_body['url']
      expect(url).to include("/portal/#{lead.reload.portal_token}")

      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/portal_link",
           headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['url']).to eq(url)
    end

    it 'devolve 401 sem autenticação' do
      lead = create(:lead, account: account, lead_stage: novo)
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/portal_link", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
