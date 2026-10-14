require 'rails_helper'

RSpec.describe 'Ramon::AvisoDaIa' do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:sdr) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:lead, account: account) }

  def avisados = Notification.where(primary_actor: lead, notification_type: 'ramon_fluxo_aviso').pluck(:user_id)

  it 'avisa o SDR/closer do lead; sem eles, os administradores' do
    Ramon::AvisoDaIa.avisar(lead, 'x', 't', 'c')
    expect(avisados).to eq([admin.id])

    Notification.delete_all
    lead.update_columns(sdr_id: sdr.id) # rubocop:disable Rails/SkipsModelValidations -- sem atribuir a conversa
    Ramon::AvisoDaIa.avisar(lead.reload, 'x', 't', 'c')
    expect(avisados).to eq([sdr.id])
  end

  it 'admins: true avisa o responsável e também os administradores (roteiro sem saída, spec §5)' do
    lead.update_columns(sdr_id: sdr.id) # rubocop:disable Rails/SkipsModelValidations -- sem atribuir a conversa
    Ramon::AvisoDaIa.avisar(lead.reload, 'x', 't', 'c', admins: true)
    expect(avisados).to contain_exactly(sdr.id, admin.id)
  end
end
