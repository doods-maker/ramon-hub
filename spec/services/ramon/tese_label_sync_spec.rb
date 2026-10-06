# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ramon::TeseLabelSync do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:bpc) { create(:thesis, account: account, name: 'BPC/LOAS') }
  let(:acidente) { create(:thesis, account: account, name: 'Auxílio-acidente') }

  it 'aplica a tese do lead como etiqueta tese-<slug>, preservando as outras', :aggregate_failures do
    conversation.update_labels(%w[urgente])
    lead = create(:lead, account: account, conversation: conversation, thesis: bpc)
    described_class.apply_to_conversation(lead)
    expect(conversation.reload.label_list).to include('urgente', 'tese-bpc-loas')
    expect(account.labels.find_by(title: 'tese-bpc-loas')).to be_present
  end

  it 'troca a tese-* antiga quando a tese do lead muda' do
    lead = create(:lead, account: account, conversation: conversation, thesis: bpc)
    lead.update!(thesis: acidente)
    described_class.apply_to_conversation(lead)
    expect(conversation.reload.label_list.grep(/\Atese-/)).to eq(['tese-auxilio-acidente'])
  end

  it 'lead sem tese tira a tese-* da conversa' do
    conversation.update_labels(%w[tese-bpc-loas urgente])
    lead = create(:lead, account: account, conversation: conversation)
    described_class.apply_to_conversation(lead)
    expect(conversation.reload.label_list.grep(/\Atese-/)).to be_empty
  end

  it 'é mão única: etiqueta tese-* posta à mão não muda a tese do lead' do
    lead = create(:lead, account: account, conversation: conversation, thesis: bpc)
    conversation.update_labels(conversation.label_list + %w[tese-auxilio-acidente])
    expect(lead.reload.thesis).to eq(bpc)
  end

  it 'lead sem conversa é no-op' do
    lead = create(:lead, account: account, thesis: bpc)
    expect { described_class.apply_to_conversation(lead) }.not_to raise_error
  end
end
