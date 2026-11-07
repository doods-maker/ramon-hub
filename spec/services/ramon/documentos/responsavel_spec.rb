require 'rails_helper'

# Quem assume a conversa em Documentos (spec §6): SDR online → closer online → SDR (ou closer) mesmo offline → ninguém.
RSpec.describe Ramon::Documentos::Responsavel do
  let(:account) { create(:account) }
  let(:sdr) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:closer) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:lead) { create(:lead, account: account, sdr: sdr, closer: closer) }

  def offline!(user) = account.account_users.find_by(user: user).update!(availability: :offline)

  it 'SDR online: o SDR' do
    expect(described_class.de(lead)).to eq(sdr)
  end

  it 'SDR offline e closer online: o closer' do
    offline!(sdr)
    expect(described_class.de(lead)).to eq(closer)
  end

  it 'os dois offline: o SDR, que alguém precisa ser dono' do
    offline!(sdr)
    offline!(closer)
    expect(described_class.de(lead)).to eq(sdr)
  end

  it 'sem SDR: o closer, mesmo offline' do
    offline!(closer)
    lead.update!(sdr: nil)
    expect(described_class.de(lead)).to eq(closer)
  end

  it 'sem SDR e sem closer: ninguém' do
    lead.update!(sdr: nil, closer: nil)
    expect(described_class.de(lead)).to be_nil
  end
end
