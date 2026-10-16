require 'rails_helper'

RSpec.describe GoogleAgendaConta do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  def nova(attrs = {})
    described_class.create!({ account: account, user: user, email: 'a@b.com', access_token: 'at', refresh_token: 'rt',
                              expira_em: 1.hour.from_now }.merge(attrs))
  end

  it 'permite uma conta por usuário' do
    nova
    duplicada = described_class.new(account: account, user: user, access_token: 'x', refresh_token: 'y')
    expect(duplicada).not_to be_valid
  end

  it '.de devolve só a conta conectada do usuário' do
    conta = nova
    expect(described_class.de(user)).to eq(conta)
    conta.update!(status: 'desconectada')
    expect(described_class.de(user)).to be_nil
  end
end
