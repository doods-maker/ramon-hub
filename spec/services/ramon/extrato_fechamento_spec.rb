require 'rails_helper'

RSpec.describe Ramon::ExtratoFechamento do
  let(:account) { create(:account) }
  let(:won_stage) { account.lead_stages.find_by(is_won: true) }
  let(:open_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }
  let(:sdr) { create(:user, account: account, role: :agent, name: 'Sara SDR') }
  let(:closer) { create(:user, account: account, role: :agent, name: 'Caio Closer') }
  let(:novembro) { Date.new(2026, 11, 1) }
  let(:dezembro) { Date.new(2026, 12, 1) }

  before do
    create(:team_member, team: create(:team, account: account, name: 'sdr'), user: sdr)
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)
  end

  def contrato_limpo(quando)
    create(:lead, account: account, lead_stage: won_stage, sdr: sdr, closer: closer, reuniao_resultado: 'qualificada').tap do |lead|
      lead.update_columns(contrato_limpo_em: quando) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def extrato(mes, user)
    described_class.pessoas(account, mes).find { |p| p[:user][:id] == user.id }
  end

  def em(data)
    Time.zone.parse("#{data} 15:00:00 UTC")
  end

  it 'fecha no 3º dia útil depois do fim do mês (seg–sex) e guarda o extrato de cada pessoa', :aggregate_failures do
    expect(described_class.data_de_fechamento(novembro)).to eq(Date.new(2026, 12, 3)) # 01/12 é terça
    expect(described_class.data_de_fechamento(Date.new(2026, 10, 1))).to eq(Date.new(2026, 11, 4)) # 01/11 é domingo
    contrato_limpo(em('2026-11-10'))

    travel_to(em('2026-12-02')) { expect(extrato(novembro, closer)).not_to have_key(:fechado_em) }
    expect(ExtratoFechado.count).to eq(0)

    travel_to(em('2026-12-03')) { expect(extrato(novembro, closer)).to include(total: 22, fechado_em: be_present) }
    expect(ExtratoFechado.where(competencia: novembro).pluck(:user_id)).to contain_exactly(sdr.id, closer.id)
  end

  it 'mês fechado não muda quando o dono do lead muda depois', :aggregate_failures do
    lead = contrato_limpo(em('2026-11-10'))
    outro = create(:user, account: account, role: :agent)

    travel_to(em('2026-12-04')) do
      described_class.fechar!(account, novembro)
      lead.update!(closer: outro)

      expect(extrato(novembro, closer)[:total]).to eq(22)
      expect(extrato(novembro, outro)).to be_nil
    end
  end

  it 'contrato pago e cancelado depois vira desconto no mês seguinte, uma vez só', :aggregate_failures do
    lead = contrato_limpo(em('2026-11-10'))
    travel_to(em('2026-12-04')) { described_class.fechar!(account, novembro) }
    travel_to(em('2026-12-10')) { lead.update!(lead_stage: open_stage) }

    expect(lead.reload).to have_attributes(contrato_limpo_em: nil, contrato_cancelado_em: be_present)
    travel_to(em('2026-12-15')) do
      expect(extrato(novembro, closer)[:total]).to eq(22)
      expect(extrato(dezembro, closer)[:unidades]).to contain_exactly(include(evento: 'desconto', lead_id: lead.id, valor: -22))
      expect(extrato(dezembro, sdr)).to include(descontos: -10, total: -10)
    end
    travel_to(em('2027-01-12')) do
      expect(extrato(dezembro, closer)).to include(total: -22, fechado_em: be_present)
      expect(extrato(Date.new(2027, 1, 1), closer)[:unidades]).to be_empty
    end
  end

  it 'Closer: se o desconto desfaz o bônus pago no mês de origem, o bônus é compensado junto' do
    MetaComercial.create!(account: account, user: closer, papel: 'closer', mes: novembro, meta: 1)
    lead = contrato_limpo(em('2026-11-10'))
    travel_to(em('2026-12-04')) { described_class.fechar!(account, novembro) }
    travel_to(em('2026-12-10')) { lead.update!(lead_stage: open_stage) }

    travel_to(em('2026-12-15')) do
      expect(extrato(dezembro, closer)[:unidades].pluck(:evento, :valor)).to eq([['desconto', -22], ['desconto_bonus', -150]])
    end
  end

  it 'cancelamento antes do fechamento só tira o contrato do mês (sem desconto)', :aggregate_failures do
    lead = contrato_limpo(em('2026-11-10'))
    travel_to(em('2026-11-20')) { lead.update!(lead_stage: open_stage) }

    travel_to(em('2026-12-15')) do
      expect(extrato(novembro, closer)[:total]).to eq(0)
      expect(extrato(dezembro, closer)[:unidades]).to be_empty
    end
  end
end
