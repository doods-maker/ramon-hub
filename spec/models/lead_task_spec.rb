require 'rails_helper'

RSpec.describe LeadTask do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }

  it 'is valid with title, kind and due_at' do
    task = described_class.new(account: account, lead: lead, title: 'Ligar', kind: 'follow_up', due_at: 1.day.from_now)
    expect(task).to be_valid
  end

  it 'requires a title' do
    expect(described_class.new(account: account, lead: lead, title: nil, due_at: 1.day.from_now)).not_to be_valid
  end

  it 'rejects an unknown kind' do
    task = described_class.new(account: account, lead: lead, title: 'x', kind: 'bogus', due_at: 1.day.from_now)
    expect(task).not_to be_valid
  end

  it 'requires a due_at' do
    expect(described_class.new(account: account, lead: lead, title: 'x', kind: 'follow_up', due_at: nil)).not_to be_valid
  end

  describe 'scopes' do
    # Comparação por id (não por objeto): igualdade de AR depende de identidade
    # de classe, que quebra em shard com reload (ver nota de specs no AGENTS.md).
    it 'open_tasks excludes completed tasks' do
      open = create(:lead_task, account: account, lead: lead)
      done = create(:lead_task, account: account, lead: lead, completed_at: Time.current)
      expect(described_class.open_tasks.ids).to include(open.id)
      expect(described_class.open_tasks.ids).not_to include(done.id)
    end

    it 'overdue returns open tasks whose due_at is in the past' do
      past = create(:lead_task, account: account, lead: lead, due_at: 1.hour.ago)
      future = create(:lead_task, account: account, lead: lead, due_at: 1.hour.from_now)
      expect(described_class.overdue.ids).to include(past.id)
      expect(described_class.overdue.ids).not_to include(future.id)
    end
  end

  describe '#complete!' do
    before { Current.user = nil }
    after { Current.user = nil }

    it 'sets completed_at and records a task_completed activity' do
      agent = create(:user, account: account)
      task = create(:lead_task, account: account, lead: lead, title: 'Enviar proposta')
      task.complete!(agent)

      expect(task.reload.completed_at).to be_present
      activity = lead.lead_activities.find_by(kind: 'task_completed')
      expect(activity).to be_present
      expect(activity.user).to eq(agent)
      expect(activity.to_value).to eq('Enviar proposta')
    end
  end

  describe 'activity on creation' do
    before { Current.user = nil }
    after { Current.user = nil }

    it 'records a task_created activity with the title' do
      agent = create(:user, account: account)
      Current.user = agent
      create(:lead_task, account: account, lead: lead, title: 'Cobrar documento')

      activity = lead.lead_activities.find_by(kind: 'task_created')
      expect(activity).to be_present
      expect(activity.user).to eq(agent)
      expect(activity.to_value).to eq('Cobrar documento')
    end
  end
end
