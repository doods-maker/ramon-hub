require 'rails_helper'

RSpec.describe ThesisItem do
  let(:thesis) { create(:thesis) }

  it 'valida presença e inclusão de section' do
    item = build(:thesis_item, thesis: thesis, section: 'invalida')
    expect(item).not_to be_valid
  end

  it 'aceita as 5 seções válidas do playbook' do
    described_class::SECTIONS.each do |section|
      item = build(:thesis_item, thesis: thesis, section: section)
      expect(item).to be_valid
    end
  end

  it 'valida presença de content' do
    item = build(:thesis_item, thesis: thesis, content: nil)
    expect(item).not_to be_valid
  end

  it 'ordena por position (default_scope)' do
    primeiro = create(:thesis_item, thesis: thesis, position: -1)
    expect(thesis.thesis_items.first).to eq(primeiro)
  end
end
