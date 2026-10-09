require 'rails_helper'

RSpec.describe Ramon::PortalSyncJob do
  let!(:cliente) { create(:portal_cliente, convidado_em: 1.day.ago) }
  let(:servico) { instance_double(Ramon::PortalSyncService, perform: true) }

  before { allow(Ramon::PortalSyncService).to receive(:new).and_return(servico) }

  it 'espelha os clientes convidados; ADVBOX fora do ar num cliente não derruba os outros' do
    outro = create(:portal_cliente, account: cliente.account, convidado_em: 1.day.ago)
    create(:portal_cliente, account: cliente.account, convidado_em: nil)
    allow(servico).to receive(:perform).and_raise(Ramon::AdvboxClient::UnavailableError, 'fora')
    expect { described_class.perform_now }.not_to raise_error
    expect(Ramon::PortalSyncService).to have_received(:new).twice
    expect(Ramon::PortalSyncService).to have_received(:new).with(outro)
  end
end
