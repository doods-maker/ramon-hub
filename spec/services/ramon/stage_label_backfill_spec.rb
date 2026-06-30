# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ramon::StageLabelBackfill do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  it 'aplica a fase-* da etapa atual em cada lead com conversa' do
    conv = create(:conversation, account: account, contact: contact)
    create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-qualificacao'),
                  conversation: conv, contact: contact)
    described_class.new(account).perform
    expect(conv.reload.label_list).to contain_exactly('fase-qualificacao')
  end

  it 'ignora leads sem conversa' do
    create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'), conversation: nil)
    expect { described_class.new(account).perform }.not_to raise_error
  end
end
