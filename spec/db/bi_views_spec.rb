require 'rails_helper'

# Views versionadas com scenic (Onda 3, Task 5). Sem model dedicado —
# consultamos direto via SQL, do jeito que o Metabase/BI vai consumir.
RSpec.describe 'BI views (bi_leads, bi_stage_transitions)' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:stage) { create(:lead_stage, account: account, probability: 40) }

  def bi_leads_row(lead_id)
    ActiveRecord::Base.connection.exec_query("SELECT * FROM bi_leads WHERE id = #{lead_id.to_i}").first
  end

  def bi_lead_ids
    ActiveRecord::Base.connection.exec_query('SELECT id FROM bi_leads').rows.flatten.map(&:to_i)
  end

  def bi_stage_transition_lead_ids
    ActiveRecord::Base.connection.exec_query('SELECT lead_id FROM bi_stage_transitions').rows.flatten.map(&:to_i)
  end

  it 'includes a funnel lead and excludes a calculo-advbox lead' do
    funil_lead = create(:lead, account: account, lead_stage: stage, source: 'whatsapp')
    calculo_lead = create(:lead, account: account, lead_stage: stage, source: Lead::FONTE_CALCULO)

    expect(bi_lead_ids).to include(funil_lead.id)
    expect(bi_lead_ids).not_to include(calculo_lead.id)
  end

  it 'coalesces a nil channel to outro' do
    lead = create(:lead, account: account, lead_stage: stage)
    # rubocop:disable Rails/SkipsModelValidations
    Lead.where(id: lead.id).update_all(channel: nil) # bypass Lead#assign_channel — simula linha antiga sem canal
    # rubocop:enable Rails/SkipsModelValidations

    expect(bi_leads_row(lead.id)['channel']).to eq('outro')
  end

  it 'reflects the current stage probability' do
    lead = create(:lead, account: account, lead_stage: stage)

    expect(bi_leads_row(lead.id)['stage_probability'].to_i).to eq(40)
  end

  it 'includes stage_changed transitions for a funnel lead and excludes them for a calculo-advbox lead' do
    other_stage = create(:lead_stage, account: account)
    funil_lead = create(:lead, account: account, lead_stage: stage, source: 'whatsapp')
    calculo_lead = create(:lead, account: account, lead_stage: stage, source: Lead::FONTE_CALCULO)

    funil_lead.update!(lead_stage: other_stage)
    calculo_lead.update!(lead_stage: other_stage)

    expect(bi_stage_transition_lead_ids).to include(funil_lead.id)
    expect(bi_stage_transition_lead_ids).not_to include(calculo_lead.id)
  end
end
