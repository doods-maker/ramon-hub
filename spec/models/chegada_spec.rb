require 'rails_helper'

RSpec.describe Chegada do
  let(:account) { create(:account) }
  let(:gabriela) { create(:user, account: account, role: :agent) }
  let(:brenda) { create(:user, account: account, role: :agent) }

  def chegada(attrs = {})
    account.chegadas.create!({ criado_por: gabriela, destinatario: brenda, cliente_nome: 'Maria' }.merge(attrs))
  end

  it 'exige nome do cliente' do
    expect(account.chegadas.new(criado_por: gabriela, destinatario: brenda)).not_to be_valid
  end

  it 'deriva o estado: resposta vence a escalada' do
    expect(chegada.estado).to eq('aguardando')
    expect(chegada(escalado_em: Time.current).estado).to eq('escalado')
    expect(chegada(escalado_em: 1.minute.ago, resposta: 'Já vou', respondido_em: Time.current).estado).to eq('respondido')
  end

  it 'transmite created e updated pra quem avisou e pra quem recebe' do
    expect { chegada }.to have_enqueued_job(ActionCableBroadcastJob)
      .with(contain_exactly(gabriela.pubsub_token, brenda.pubsub_token), 'ramon.chegada.created', hash_including(cliente_nome: 'Maria'))

    registro = chegada
    expect { registro.update!(resposta: 'Já vou', respondido_em: Time.current) }
      .to have_enqueued_job(ActionCableBroadcastJob).with(contain_exactly(gabriela.pubsub_token, brenda.pubsub_token), 'ramon.chegada.updated', hash_including(estado: 'respondido'))
  end

  it 'reconhece quem é da Recepção pelo time' do
    time = create(:team, account: account, name: Chegada::RECEPCAO)
    create(:team_member, team: time, user: gabriela)

    expect(described_class.recepcao?(account, gabriela)).to be(true)
    expect(described_class.recepcao?(account, brenda)).to be(false)
  end

  it 'de_hoje usa o dia de São Paulo, não o de UTC' do
    manha_sp = travel_to(Time.zone.parse('2026-10-02 12:00:00 UTC')) { chegada } # 09:00 de 02/10 em SP
    ontem_sp = travel_to(Time.zone.parse('2026-10-02 02:00:00 UTC')) { chegada } # 23:00 de 01/10 em SP

    travel_to Time.zone.parse('2026-10-03 01:00:00 UTC') do # 22:00 de 02/10 em SP
      expect(account.chegadas.de_hoje).to include(manha_sp)
      expect(account.chegadas.de_hoje).not_to include(ontem_sp)
    end
  end
end
