# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MetaEvento do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account) }
  let(:attrs) do
    { account: account, lead: lead, evento: 'LeadSubmitted', event_id: "lead-#{lead.id}-LeadSubmitted", ocorrido_em: Time.zone.now }
  end

  it 'aceita um evento da lista' do
    expect(described_class.new(attrs)).to be_valid
  end

  it 'recusa evento fora da lista' do
    expect(described_class.new(attrs.merge(evento: 'Outro'))).not_to be_valid
  end

  it 'não repete o mesmo evento para o mesmo lead' do
    described_class.create!(attrs)
    expect { described_class.new(attrs).save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
