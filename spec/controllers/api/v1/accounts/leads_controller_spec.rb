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

    it 'caixa com Portaria: 204 e não cria lead ao abrir a conversa' do
      inbox = create(:inbox, account: account, portaria_enabled: true)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      expect do
        post "/api/v1/accounts/#{account.id}/leads/for_conversation",
             params: { conversation_id: conversation.display_id },
             headers: admin.create_new_auth_token, as: :json
      end.not_to(change(account.leads, :count))
      expect(response).to have_http_status(:no_content)
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

  describe 'POST /api/v1/accounts/{account}/leads/encaminhar_comercial' do
    let(:contact) { create(:contact, account: account) }
    let(:inbox) { create(:inbox, account: account, portaria_enabled: true) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
    let!(:comercial) { create(:team, account: account, name: 'Comercial') }

    it 'move a conversa pro time Comercial e cria o lead como indicação' do
      expect do
        post "/api/v1/accounts/#{account.id}/leads/encaminhar_comercial",
             params: { conversation_id: conversation.display_id },
             headers: admin.create_new_auth_token, as: :json
      end.to change(account.leads, :count).by(1)
      expect(response).to have_http_status(:success)
      expect(conversation.reload.team).to eq(comercial)
      lead = account.leads.last
      expect(lead.conversation_id).to eq(conversation.id)
      expect(lead.channel).to eq('indicacao')
      expect(response.parsed_body['id']).to eq(lead.id)
    end

    it 'reaponta o lead aberto do contato em vez de duplicar' do
      existing = create(:lead, account: account, contact: contact, lead_stage: novo,
                               conversation: create(:conversation, account: account, contact: contact))
      expect do
        post "/api/v1/accounts/#{account.id}/leads/encaminhar_comercial",
             params: { conversation_id: conversation.display_id },
             headers: admin.create_new_auth_token, as: :json
      end.not_to(change(account.leads, :count))
      expect(response.parsed_body['id']).to eq(existing.id)
      expect(existing.reload.conversation_id).to eq(conversation.id)
    end

    it '404 sem o time Comercial' do
      comercial.destroy!
      post "/api/v1/accounts/#{account.id}/leads/encaminhar_comercial",
           params: { conversation_id: conversation.display_id },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
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

    it 'busca q por telefone formatado casando os dígitos do E.164' do
      contato = create(:contact, account: account, phone_number: '+5548998123456')
      hit = account.leads.create!(name: 'Fulano', lead_stage: novo, contact: contato)
      account.leads.create!(name: 'Outro', lead_stage: novo)
      ['(48) 99812-3456', '99812-3456'].each do |q|
        get "/api/v1/accounts/#{account.id}/leads", params: { q: q }, headers: admin.create_new_auth_token
        expect(ids(response)).to eq([hit.id])
      end
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

    describe 'atalhos dos KPIs do Centro de Comando' do
      around { |example| travel_to(Time.utc(2026, 10, 7, 13, 0, 0)) { example.run } } # quarta, 10h em São Paulo

      def leads_with(params)
        get "/api/v1/accounts/#{account.id}/leads", params: params, headers: admin.create_new_auth_token
        ids(response)
      end

      it 'filtra por overdue_task (tarefa aberta já vencida)' do
        vencida = account.leads.create!(name: 'Vencida', lead_stage: novo)
        create(:lead_task, account: account, lead: vencida, due_at: 1.hour.ago)
        futura = account.leads.create!(name: 'Futura', lead_stage: novo)
        create(:lead_task, account: account, lead: futura, due_at: 1.day.from_now)
        feita = account.leads.create!(name: 'Feita', lead_stage: novo)
        create(:lead_task, account: account, lead: feita, due_at: 1.hour.ago, completed_at: Time.current)
        expect(leads_with(overdue_task: 'true')).to eq([vencida.id])
      end

      it 'filtra por task_due_today no dia de São Paulo' do
        hoje = account.leads.create!(name: 'Hoje', lead_stage: novo)
        create(:lead_task, account: account, lead: hoje, due_at: Time.utc(2026, 10, 8, 2, 0, 0)) # 23h SP de 07/10
        amanha = account.leads.create!(name: 'Amanhã', lead_stage: novo)
        create(:lead_task, account: account, lead: amanha, due_at: Time.utc(2026, 10, 8, 4, 0, 0)) # 01h SP de 08/10
        expect(leads_with(task_due_today: 'true')).to eq([hoje.id])
      end

      it 'filtra por won_since (desde 00h da data em São Paulo) junto com a etapa' do
        ganho = account.lead_stages.find_by(is_won: true)
        da_semana = account.leads.create!(name: 'Semana', lead_stage: ganho)
        antigo = account.leads.create!(name: 'Antigo', lead_stage: ganho)
        antigo.update_column(:won_at, Time.utc(2026, 10, 5, 2, 0, 0)) # rubocop:disable Rails/SkipsModelValidations
        account.leads.create!(name: 'Aberto', lead_stage: novo)
        expect(leads_with(won_since: '2026-10-05', lead_stage_id: ganho.id)).to eq([da_semana.id])
      end

      it 'filtra por new_from_lp com a mesma regra do radar (LP, 48h, ninguém tocou)' do
        da_lp = account.leads.create!(name: 'LP', lead_stage: novo, source: 'lp-auxilio')
        tocado = account.leads.create!(name: 'Tocado', lead_stage: novo, source: 'lp-auxilio')
        create(:lead_task, account: account, lead: tocado)
        account.leads.create!(name: 'Sem fonte', lead_stage: novo)
        expect(leads_with(new_from_lp: 'true')).to eq([da_lp.id])
      end
    end

    describe 'janela de 90 dias dos ganhos/perdidos' do
      let(:ganho) { account.lead_stages.find_by(is_won: true) }
      let!(:aberto_antigo) { travel_to(200.days.ago) { account.leads.create!(name: 'Aberto antigo', lead_stage: novo) } }
      let!(:ganho_recente) { travel_to(10.days.ago) { account.leads.create!(name: 'Ganho recente', lead_stage: ganho) } }
      let!(:ganho_antigo) { travel_to(120.days.ago) { account.leads.create!(name: 'Ganho antigo', lead_stage: ganho) } }
      let!(:perdido_recente) { travel_to(5.days.ago) { account.leads.create!(name: 'Perdido recente', lead_stage: perdido, lost_reason: 'x') } }
      let!(:perdido_antigo) { travel_to(150.days.ago) { account.leads.create!(name: 'Perdido antigo', lead_stage: perdido, lost_reason: 'x') } }

      def leads_with(params = {})
        get "/api/v1/accounts/#{account.id}/leads", params: params, headers: admin.create_new_auth_token
        ids(response)
      end

      it 'por padrão traz abertos de qualquer idade e só fechados dos últimos 90 dias' do
        expect(leads_with).to contain_exactly(aberto_antigo.id, ganho_recente.id, perdido_recente.id)
      end

      it 'closed_all traz todos os fechados' do
        expect(leads_with(closed_all: 'true'))
          .to contain_exactly(aberto_antigo.id, ganho_recente.id, ganho_antigo.id, perdido_recente.id, perdido_antigo.id)
      end

      it 'won_since anterior à janela não é cortado' do
        since = 130.days.ago.in_time_zone('America/Sao_Paulo').to_date.iso8601
        expect(leads_with(won_since: since)).to contain_exactly(ganho_recente.id, ganho_antigo.id)
      end

      it 'filtro pela etapa ganha traz o histórico da etapa' do
        expect(leads_with(lead_stage_id: ganho.id)).to contain_exactly(ganho_recente.id, ganho_antigo.id)
      end

      it 'busca por nome acha o fechado antigo' do
        expect(leads_with(q: 'Perdido antigo')).to eq([perdido_antigo.id])
      end
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

  describe 'papéis: só o gestor troca SDR/Closer' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:lead) { create(:lead, account: account, lead_stage: novo) }

    it 'agente recebe 403 ao trocar o SDR', :aggregate_failures do
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { sdr_id: agent.id }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(lead.reload.sdr_id).to be_nil
    end

    it 'agente edita o resto mandando o mesmo SDR de volta' do
      lead.update!(sdr_id: agent.id)
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { sdr_id: agent.id, name: 'Novo nome' }, headers: agent.create_new_auth_token, as: :json
      expect(lead.reload.name).to eq('Novo nome')
    end

    it 'gestor troca o Closer' do
      patch "/api/v1/accounts/#{account.id}/leads/#{lead.id}",
            params: { closer_id: agent.id }, headers: admin.create_new_auth_token, as: :json
      expect(lead.reload.closer_id).to eq(agent.id)
    end

    it 'agente criando lead não escolhe dono (ignorado)' do
      post "/api/v1/accounts/#{account.id}/leads",
           params: { name: 'X', lead_stage_id: novo.id, closer_id: agent.id }, headers: agent.create_new_auth_token, as: :json
      expect(account.leads.find_by(name: 'X').closer_id).to be_nil
    end
  end

  describe 'POST /leads/:id/reuniao (reunião qualificada)' do
    let(:closer) { create(:user, account: account, role: :agent) }
    let(:outro) { create(:user, account: account, role: :agent) }
    let(:lead) { create(:lead, account: account, lead_stage: novo) }
    let(:realizada) { account.lead_stages.find_by(label: 'fase-reuniao-realizada') }

    def registrar(user, resultado = 'qualificada')
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/reuniao",
           params: { resultado: resultado }, headers: user.create_new_auth_token, as: :json
    end

    it 'Closer do lead marca: grava, anda pra Reunião realizada e registra a atividade', :aggregate_failures do
      lead.update!(closer: closer)
      registrar(closer)

      expect(response).to have_http_status(:success)
      lead.reload
      expect(lead.reuniao_resultado).to eq('qualificada')
      expect(lead.reuniao_registrada_em).to be_present
      expect(lead.lead_stage).to eq(realizada)
      expect(lead.lead_activities.find_by(kind: 'reuniao_registrada').to_value).to eq('qualificada')
    end

    it 'membro do time closer marca lead sem Closer e vira o Closer dele' do
      create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)
      registrar(closer, 'nao_qualificada')

      expect(lead.reload.closer).to eq(closer)
    end

    it 'quem não é o Closer do lead recebe 401', :aggregate_failures do
      lead.update!(closer: closer)
      registrar(outro)

      expect(response).to have_http_status(:unauthorized)
      expect(lead.reload.reuniao_resultado).to be_nil
    end

    it 'correção mantém a 1ª data (mês da apuração não muda)' do
      lead.update!(closer: closer, reuniao_resultado: 'nao_qualificada', reuniao_registrada_em: 3.days.ago.change(usec: 0))
      expect { registrar(closer) }.not_to(change { lead.reload.reuniao_registrada_em })
    end

    it 'vou_pensar grava a marca à parte, sem mexer no resultado', :aggregate_failures do
      lead.update!(closer: closer)
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/reuniao",
           params: { resultado: 'qualificada', vou_pensar: true }, headers: closer.create_new_auth_token, as: :json

      expect(lead.reload.reuniao_resultado).to eq('qualificada')
      expect(lead.lead_activities.where(kind: 'vou_pensar').count).to eq(1)
    end

    it 'resultado inválido dá 422' do
      registrar(admin, 'talvez')
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'conclui a reunião de hoje e deixa a futura aberta', :aggregate_failures do
      lead.update!(closer: closer)
      hoje = create(:lead_task, account: account, lead: lead, kind: 'meeting', due_at: 1.hour.ago)
      futura = create(:lead_task, account: account, lead: lead, kind: 'meeting', due_at: 3.days.from_now)
      registrar(closer)

      expect(hoje.reload.completed_at).to be_present
      expect(futura.reload.completed_at).to be_nil
    end

    it 'com task_id conclui exatamente aquela reunião' do
      lead.update!(closer: closer)
      futura = create(:lead_task, account: account, lead: lead, kind: 'meeting', due_at: 3.days.from_now)
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/reuniao",
           params: { resultado: 'nao_qualificada', task_id: futura.id }, headers: closer.create_new_auth_token, as: :json

      expect(futura.reload.completed_at).to be_present
    end
  end

  describe 'docs_completos_em (base do contrato limpo)' do
    let(:thesis) { create(:thesis, account: account) }

    it 'carimba quando a checklist inteira fica recebida e apaga ao desmarcar', :aggregate_failures do
      ids = create_list(:thesis_item, 2, thesis: thesis, section: 'documento').map(&:id)
      lead = create(:lead, account: account, lead_stage: novo, thesis: thesis)
      todos = ids.index_with { 'recebido' }.transform_keys(&:to_s)

      lead.update!(custom_attributes: { 'doc_status' => todos })
      expect(lead.reload.docs_completos_em).to be_present

      lead.update!(custom_attributes: { 'doc_status' => todos.merge(ids.first.to_s => 'pendente') })
      expect(lead.reload.docs_completos_em).to be_nil
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

  describe 'POST /api/v1/accounts/:account_id/leads/:id/follow_up_draft' do
    let(:conversation) { create(:conversation, account: account) }
    let(:lead) { create(:lead, account: account, lead_stage: novo, conversation_id: conversation.id) }

    def post_draft(target = lead)
      post "/api/v1/accounts/#{account.id}/leads/#{target.id}/follow_up_draft",
           headers: admin.create_new_auth_token, as: :json
    end

    it 'enfileira o job de retomada e devolve 202' do
      expect { post_draft }.to have_enqueued_job(Ramon::FollowUpDraftJob).with(lead.id)
      expect(response).to have_http_status(:accepted)
    end

    it 'lead sem conversa → 422 no_conversation, sem enfileirar' do
      sem_conversa = create(:lead, account: account, lead_stage: novo)
      expect { post_draft(sem_conversa) }.not_to have_enqueued_job(Ramon::FollowUpDraftJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'FOLLOW_UP_NOT_ELIGIBLE', 'reason' => 'no_conversation')
    end

    it 'tarefa follow_up aberta → 422 open_follow_up, sem enfileirar' do
      lead.lead_tasks.create!(account: account, kind: 'follow_up', title: 'Ligar', due_at: 1.day.from_now)
      expect { post_draft }.not_to have_enqueued_job(Ramon::FollowUpDraftJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['reason']).to eq('open_follow_up')
    end

    it 'retomada há menos de 5 dias → 422 recent_follow_up com data e dias' do
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1, 'ultima_em' => 2.days.ago.iso8601 } })
      expect { post_draft }.not_to have_enqueued_job(Ramon::FollowUpDraftJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('reason' => 'recent_follow_up', 'days_ago' => 2, 'min_gap_days' => 5)
      expect(response.parsed_body['last_at']).to be_present
    end

    it 'retomada há mais de 5 dias → 202' do
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1, 'ultima_em' => 6.days.ago.iso8601 } })
      expect { post_draft }.to have_enqueued_job(Ramon::FollowUpDraftJob).with(lead.id)
      expect(response).to have_http_status(:accepted)
    end

    it 'devolve 401 sem autenticação' do
      lead = create(:lead, account: account, lead_stage: novo)
      post "/api/v1/accounts/#{account.id}/leads/#{lead.id}/follow_up_draft", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
