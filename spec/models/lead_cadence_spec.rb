require 'rails_helper'

RSpec.describe Lead do
  let(:account) { create(:account) }
  let(:active_stage) { account.lead_stages.find_by(name: 'Qualificação') }
  let(:won_stage) { account.lead_stages.find_by(is_won: true) }
  let(:lost_stage) { account.lead_stages.find_by(is_lost: true) }

  describe 'stage cycle tracking' do
    it 'sets stage_entered_at when the stage changes' do
      lead = create(:lead, account: account, lead_stage: active_stage)
      original = lead.stage_entered_at
      travel_to(1.hour.from_now) do
        lead.update!(lead_stage: account.lead_stages.find_by(name: 'Reunião agendada'))
        expect(lead.stage_entered_at).to be > original
      end
    end

    it 'stamps won_at and keeps lost_at nil when moving to the won stage' do
      lead = create(:lead, account: account, lead_stage: active_stage)
      lead.update!(lead_stage: won_stage)
      expect(lead.won_at).to be_present
      expect(lead.lost_at).to be_nil
    end

    it 'stamps lost_at when moving to the lost stage' do
      lead = create(:lead, account: account, lead_stage: active_stage)
      lead.update!(lead_stage: lost_stage, lost_reason: 'Honorário')
      expect(lead.lost_at).to be_present
      expect(lead.lost_reason).to eq('Honorário')
    end

    it 'clears won_at, lost_at and lost_reason when returning to an active stage' do
      lead = create(:lead, account: account, lead_stage: lost_stage, lost_reason: 'Honorário')
      lead.update!(lead_stage: active_stage)
      expect(lead.won_at).to be_nil
      expect(lead.lost_at).to be_nil
      expect(lead.lost_reason).to be_nil
    end
  end

  describe '#stalled?' do
    it 'is true when stage_entered_at is beyond the stage limit' do
      lead = create(:lead, account: account, lead_stage: active_stage)
      lead.update!(stage_entered_at: 5.days.ago)
      expect(lead.stalled?).to be(true)
    end

    it 'is false when the stage has no stalled_after_days' do
      stage = account.lead_stages.find_by(name: 'Reunião agendada')
      lead = create(:lead, account: account, lead_stage: stage)
      lead.update!(stage_entered_at: 30.days.ago)
      expect(lead.stalled?).to be(false)
    end
  end

  describe '#push_event_data' do
    it 'includes the cadence keys and open task count' do
      lead = create(:lead, account: account, lead_stage: active_stage)
      create(:lead_task, account: account, lead: lead, due_at: 2.days.from_now)

      data = lead.push_event_data
      expect(data).to include(:stage_entered_at, :won_at, :lost_at, :stalled, :next_task_due_at, :contact_phone)
      expect(data[:open_tasks_count]).to eq(1)
    end
  end
end
