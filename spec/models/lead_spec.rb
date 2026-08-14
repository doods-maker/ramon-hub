require 'rails_helper'

RSpec.describe Lead do
  let(:account) { create(:account) }

  it 'pertence a uma etapa e expõe push_event_data' do
    stage = create(:lead_stage, account: account, name: 'Etapa 3A')
    lead = create(:lead, account: account, lead_stage: stage, name: 'João')

    expect(lead.lead_stage).to eq(stage)
    expect(lead.push_event_data).to include(id: lead.id, name: 'João', lead_stage_id: stage.id)
  end

  it 'exige etapa' do
    lead = build(:lead, account: account, lead_stage: nil)
    expect(lead).not_to be_valid
  end

  it 'dispara LEAD_CREATED ao criar' do
    stage = create(:lead_stage, account: account, name: 'Etapa Disp')
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::LEAD_CREATED, anything, hash_including(:lead))
    create(:lead, account: account, lead_stage: stage)
  end

  it 'dispara LEAD_UPDATED ao atualizar' do
    stage = create(:lead_stage, account: account, name: 'Etapa Disp2')
    lead = create(:lead, account: account, lead_stage: stage)
    expect(Rails.configuration.dispatcher).to receive(:dispatch)
      .with(Events::Types::LEAD_UPDATED, anything, hash_including(:lead))
    lead.update!(name: 'Novo Nome')
  end

  it 'expõe as colunas A1 (value, source)' do
    expect(described_class.column_names).to include('value', 'source')
  end

  it 'push_event_data inclui os campos do card rico' do
    stage = account.lead_stages.find_by(name: 'Negociação')
    lead = create(:lead, account: account, lead_stage: stage, value: 5000, source: 'Indicação')
    data = lead.push_event_data
    expect(data).to include(
      value: 5000.0, source: 'Indicação',
      stage_name: 'Negociação', stage_color: '#f59e0b'
    )
    expect(data.keys).to include(:benefit_type_name, :lead_priority_name, :sdr_name, :closer_name, :contact_name)
  end

  it 'push_event_data serializa value como Float (BigDecimal quebra o broadcast no Sidekiq)' do
    lead = create(:lead, account: account, value: 5000)
    expect(lead.push_event_data[:value]).to be_a(Float)
  end

  it 'push_event_data expõe kit_status na latest_triage' do
    lead = create(:lead, account: account)
    agent = account.triage_agents.first
    lead.lead_triages.create!(account: account, triage_agent: agent, status: 'done', kit_status: 'ready')
    expect(lead.push_event_data[:latest_triage][:kit_status]).to eq('ready')
  end

  describe 'scopes de funil (caso de cálculo)' do
    let(:stage) { account.lead_stages.order(:position).first }
    let!(:lead_normal) { create(:lead, account: account, lead_stage: stage, source: nil) }
    let!(:lead_lp) { create(:lead, account: account, lead_stage: stage, source: 'lp-auxilio-acidente') }
    let!(:caso_calculo) { create(:lead, account: account, lead_stage: stage, source: Lead::FONTE_CALCULO) }

    it 'funil exclui caso de cálculo e mantém source NULL (IS DISTINCT FROM)' do
      expect(account.leads.funil).to contain_exactly(lead_normal, lead_lp)
    end

    it 'open não adota caso de cálculo como lead vivo' do
      expect(account.leads.open).to include(lead_normal)
      expect(account.leads.open).not_to include(caso_calculo)
    end
  end

  describe '#prescription' do
    let(:stage) { account.lead_stages.first }

    it 'returns nil without dcb_em' do
      lead = create(:lead, account: account, lead_stage: stage)
      expect(lead.prescription).to be_nil
    end

    it 'computes months and lost installments past the 60-month window' do
      lead = create(:lead, account: account, lead_stage: stage,
                           dcb_em: Date.new(2020, 1, 15), benefit_monthly_value: 800)
      travel_to Date.new(2026, 7, 6) do
        p = lead.prescription
        expect(p[:months_since_dcb]).to eq(77)
        expect(p[:lost_installments]).to eq(17)
        expect(p[:lost_value]).to eq(BigDecimal(13_600))
      end
    end

    it 'reports zero lost inside the window and nil value without monthly' do
      lead = create(:lead, account: account, lead_stage: stage, dcb_em: 2.years.ago.to_date)
      p = lead.prescription
      expect(p[:lost_installments]).to eq(0)
      expect(p[:lost_value]).to be_nil
    end
  end

  describe '#assign_channel' do
    it 'canal manual explícito vence e não é sobrescrito pelo derive' do
      lead = create(:lead, account: account, source: 'anuncio-meta: 1', channel: 'whatsapp_direto')
      expect(lead.channel).to eq('whatsapp_direto')
    end

    it 'deriva o canal do source quando channel fica em branco' do
      lead = create(:lead, account: account, source: 'Indicação da Maria')
      expect(lead.channel).to eq('indicacao')
    end

    it 'cai em outro quando nenhuma regra casa' do
      lead = create(:lead, account: account, source: 'campanha desconhecida')
      expect(lead.channel).to eq('outro')
    end
  end

  context 'when recording lead activities' do
    before { Current.user = nil }
    after { Current.user = nil }

    it 'records a created activity on creation' do
      lead = create(:lead, account: account)
      activity = lead.lead_activities.find_by(kind: 'created')
      expect(activity).to be_present
      expect(activity.user).to be_nil
    end

    it 'records a stage_changed activity with labels and author on stage update' do
      agent = create(:user, account: account)
      novo = create(:lead_stage, account: account, name: 'Fase A')
      prox = create(:lead_stage, account: account, name: 'Fase B')
      lead = create(:lead, account: account, lead_stage: novo)
      Current.user = agent
      lead.update!(lead_stage: prox)
      act = lead.lead_activities.find_by(kind: 'stage_changed')
      expect(act.from_value).to eq('Fase A')
      expect(act.to_value).to eq('Fase B')
      expect(act.user).to eq(agent)
    end

    it 'records a value_changed activity' do
      lead = create(:lead, account: account, value: 100)
      lead.update!(value: 250)
      act = lead.lead_activities.find_by(kind: 'value_changed')
      expect(act.from_value).to eq('100.0')
      expect(act.to_value).to eq('250.0')
    end
  end

  describe 'fechamento -> AdvBox (item 21)' do
    it 'enfileira o job quando o lead vira ganho com token configurado' do
      with_modified_env ADVBOX_API_TOKEN: 'tok' do
        lead = create(:lead, account: account)
        won = account.lead_stages.find_by!(is_won: true)
        expect { lead.update!(lead_stage: won) }
          .to have_enqueued_job(Ramon::AdvboxClosingJob).with(lead.id)
      end
    end

    it 'nao enfileira sem ADVBOX_API_TOKEN' do
      with_modified_env ADVBOX_API_TOKEN: nil do
        lead = create(:lead, account: account)
        won = account.lead_stages.find_by!(is_won: true)
        expect { lead.update!(lead_stage: won) }
          .not_to have_enqueued_job(Ramon::AdvboxClosingJob)
      end
    end
  end

  describe 'NPS pós-fechamento (mapa comercial)' do
    it 'enfileira o NpsDraftJob quando o lead vira ganho' do
      lead = create(:lead, account: account)
      won = account.lead_stages.find_by!(is_won: true)
      expect { lead.update!(lead_stage: won) }
        .to have_enqueued_job(Ramon::NpsDraftJob).with(lead.id)
    end

    it 'não enfileira quando o lead sai de ganho (won_at limpo)' do
      lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by!(is_won: true))
      open_stage = account.lead_stages.find_by(is_won: false, is_lost: false)
      expect { lead.update!(lead_stage: open_stage) }
        .not_to have_enqueued_job(Ramon::NpsDraftJob)
    end
  end

  describe 'ponte Drive (ADR-0002)' do
    let(:drive_env) { { RAMON_DRIVE_CREDENTIALS: 'path/to/creds.json', RAMON_DRIVE_ROOT_ID: 'root-id' } }

    it 'enfileira o DriveExportJob quando o lead vira ganho com as duas envs configuradas' do
      with_modified_env drive_env do
        lead = create(:lead, account: account)
        won = account.lead_stages.find_by!(is_won: true)
        expect { lead.update!(lead_stage: won) }
          .to have_enqueued_job(Ramon::DriveExportJob).with(lead.id)
      end
    end

    it 'nao enfileira sem RAMON_DRIVE_CREDENTIALS' do
      with_modified_env drive_env.merge(RAMON_DRIVE_CREDENTIALS: nil) do
        lead = create(:lead, account: account)
        won = account.lead_stages.find_by!(is_won: true)
        expect { lead.update!(lead_stage: won) }
          .not_to have_enqueued_job(Ramon::DriveExportJob)
      end
    end

    it 'nao enfileira sem RAMON_DRIVE_ROOT_ID mesmo com RAMON_DRIVE_CREDENTIALS setada' do
      with_modified_env drive_env.merge(RAMON_DRIVE_ROOT_ID: nil) do
        lead = create(:lead, account: account)
        won = account.lead_stages.find_by!(is_won: true)
        expect { lead.update!(lead_stage: won) }
          .not_to have_enqueued_job(Ramon::DriveExportJob)
      end
    end

    it 'reenfileira em qualquer update de custom_attributes de lead ja ganho' do
      with_modified_env drive_env do
        lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by!(is_won: true))
        expect { lead.update!(custom_attributes: { 'doc_status' => { '1' => 'recebido' } }) }
          .to have_enqueued_job(Ramon::DriveExportJob).with(lead.id)
      end
    end
  end

  describe '#docs_counts' do
    let(:thesis) { create(:thesis, account: account) }
    let!(:doc_item) { create(:thesis_item, thesis: thesis, section: 'documento', content: 'RG') }

    # item de outra seção não pode entrar na contagem
    before { create(:thesis_item, thesis: thesis, section: 'colheita', content: 'Renda') }

    it 'conta so itens de documento, com recebido vindo do doc_status' do
      lead = create(:lead, account: account, thesis: thesis,
                           custom_attributes: { 'doc_status' => { doc_item.id.to_s => 'recebido' } })
      expect(lead.docs_counts).to eq(received: 1, total: 1)
    end

    it 'zera sem tese' do
      lead = create(:lead, account: account)
      expect(lead.docs_counts).to eq(received: 0, total: 0)
    end
  end

  describe '#ensure_portal_token!' do
    it 'gera o token sob demanda, persiste e reusa nas chamadas seguintes' do
      lead = create(:lead, account: account)
      expect(lead.portal_token).to be_nil

      token = lead.ensure_portal_token!
      expect(token).to be_present
      expect(lead.reload.portal_token).to eq(token)
      expect(lead.ensure_portal_token!).to eq(token)
    end

    it 'gera tokens diferentes para leads diferentes' do
      first = create(:lead, account: account)
      second = create(:lead, account: account)
      expect(first.ensure_portal_token!).not_to eq(second.ensure_portal_token!)
    end
  end
end
