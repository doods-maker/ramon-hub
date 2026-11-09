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

  # contrato apto do Closer (Ramon::ContratoApto); R$ 30 + DSR de nov/2026 (7/23) = R$ 39,13
  def contrato_apto(quando)
    create(:lead, account: account, lead_stage: won_stage, sdr: sdr, closer: closer).tap do |lead|
      lead.update_columns(contrato_limpo_em: quando - 7.days, validacao_desde: quando - 7.days, apto_em: quando) # rubocop:disable Rails/SkipsModelValidations
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
    contrato_apto(em('2026-11-10'))

    travel_to(em('2026-12-02')) { expect(extrato(novembro, closer)).not_to have_key(:fechado_em) }
    expect(ExtratoFechado.count).to eq(0)

    travel_to(em('2026-12-03')) { expect(extrato(novembro, closer)).to include(total: 39.13, fechado_em: be_present) }
    expect(ExtratoFechado.where(competencia: novembro).pluck(:user_id)).to contain_exactly(sdr.id, closer.id)
  end

  it 'mês fechado não muda quando o dono do lead muda depois', :aggregate_failures do
    lead = contrato_apto(em('2026-11-10'))
    outro = create(:user, account: account, role: :agent)

    travel_to(em('2026-12-04')) do
      described_class.fechar!(account, novembro)
      lead.update!(closer: outro)

      expect(extrato(novembro, closer)[:total]).to eq(39.13)
      expect(extrato(novembro, outro)).to be_nil
    end
  end

  it 'contrato cancelado depois de apto continua pago: sem desconto no mês seguinte', :aggregate_failures do
    lead = contrato_apto(em('2026-11-10'))
    travel_to(em('2026-12-04')) { described_class.fechar!(account, novembro) }
    travel_to(em('2026-12-10')) { lead.update!(lead_stage: open_stage) }

    expect(lead.reload).to have_attributes(apto_em: be_present, contrato_cancelado_em: be_present)
    travel_to(em('2026-12-15')) do
      expect(extrato(novembro, closer)[:total]).to eq(39.13)
      expect(extrato(dezembro, closer)[:unidades]).to be_empty
    end
  end
end
