require 'rails_helper'

RSpec.describe Ramon::LeadBulkActionJob do
  # create(:account) seeda o funil (etapas, agente de triagem etc.)
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:stage) { account.lead_stages.order(:position).first }
  let(:target) { account.lead_stages.order(:position).second }
  let!(:lead_a) { create(:lead, account: account, lead_stage: stage, name: 'Ana') }
  let!(:lead_b) { create(:lead, account: account, lead_stage: stage, name: 'Bia') }

  def run(params)
    described_class.perform_now(account.id, user.id, params)
  end

  it 'moves every lead in the batch to the target stage' do
    run('ids' => [lead_a.id, lead_b.id], 'fields' => { 'lead_stage_id' => target.id })

    expect(lead_a.reload.lead_stage_id).to eq(target.id)
    expect(lead_b.reload.lead_stage_id).to eq(target.id)
  end

  it 'assigns the SDR in bulk' do
    run('ids' => [lead_a.id, lead_b.id], 'fields' => { 'sdr_id' => user.id })

    expect(lead_a.reload.sdr_id).to eq(user.id)
    expect(lead_b.reload.sdr_id).to eq(user.id)
  end

  it 'applies the lost reason together with the move to a lost stage' do
    lost_stage = create(:lead_stage, account: account, name: 'Perda lote', is_lost: true)
    run('ids' => [lead_a.id], 'fields' => { 'lead_stage_id' => lost_stage.id, 'lost_reason' => 'Sem retorno' })

    expect(lead_a.reload.lead_stage_id).to eq(lost_stage.id)
    expect(lead_a.reload.lost_reason).to eq('Sem retorno')
  end

  it 'creates a follow_up task per lead' do
    due_at = 2.days.from_now.change(usec: 0)
    run('ids' => [lead_a.id, lead_b.id], 'task' => { 'due_at' => due_at.iso8601, 'title' => 'Retomar' })

    task = lead_a.lead_tasks.last
    expect(task.kind).to eq('follow_up')
    expect(task.title).to eq('Retomar')
    expect(lead_b.lead_tasks.count).to eq(1)
  end

  it 'keeps processing the batch when one lead fails' do
    allow_any_instance_of(Lead).to receive(:update!).and_wrap_original do |original, *args|
      raise 'boom' if original.receiver.id == lead_a.id

      original.call(*args)
    end

    expect do
      run('ids' => [lead_a.id, lead_b.id], 'fields' => { 'lead_stage_id' => target.id })
    end.not_to raise_error
    expect(lead_b.reload.lead_stage_id).to eq(target.id)
  end

  it 'creates a triage per lead and enqueues the TriageJob when an active agent exists' do
    account.triage_agents.create!(name: 'Bulk agent', system_prompt: 'p') if account.triage_agents.active.none?

    expect do
      run('ids' => [lead_a.id], 'triage' => 'true')
    end.to have_enqueued_job(Leads::TriageJob)
    expect(lead_a.lead_triages.count).to eq(1)
  end

  it 'skips the triage silently when there is no active agent' do
    account.triage_agents.update_all(active: false)

    expect do
      run('ids' => [lead_a.id], 'triage' => 'true')
    end.not_to have_enqueued_job(Leads::TriageJob)
    expect(lead_a.lead_triages.count).to eq(0)
  end

  it 'ignores leads from other accounts' do
    other = create(:lead)
    run('ids' => [other.id], 'fields' => { 'lead_stage_id' => target.id })

    expect(other.reload.lead_stage_id).not_to eq(target.id)
  end
end
