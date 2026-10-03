require 'rails_helper'

RSpec.describe Ramon::ExtratoVariavel do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.order(:position).first }
  let(:sdr) { create(:user, account: account, role: :agent, name: 'Sara SDR') }
  let(:closer) { create(:user, account: account, role: :agent, name: 'Caio Closer') }
  let(:mes) { Date.new(2026, 11, 1) }
  let(:em_novembro) { Time.zone.parse('2026-11-10 15:00:00 UTC') }

  before do
    create(:team_member, team: create(:team, account: account, name: 'sdr'), user: sdr)
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)
  end

  def lead(**attrs)
    create(:lead, account: account, lead_stage: stage, sdr: sdr, closer: closer, **attrs)
  end

  def extrato_de(user)
    described_class.new(account: account, mes: mes).pessoas.find { |p| p[:user][:id] == user.id }
  end

  it 'SDR: R$6 por reunião qualificada + R$10 por contrato limpo originado', :aggregate_failures do
    lead(reuniao_resultado: 'qualificada', reuniao_registrada_em: em_novembro)
    lead(reuniao_resultado: 'nao_qualificada', reuniao_registrada_em: em_novembro)
    lead(reuniao_resultado: 'qualificada', reuniao_registrada_em: em_novembro, contrato_limpo_em: em_novembro)
    lead(reuniao_resultado: 'qualificada', reuniao_registrada_em: Time.zone.parse('2026-10-31 12:00:00 UTC'))

    linha = extrato_de(sdr)
    expect(linha[:papel]).to eq('sdr')
    expect(linha[:contagem]).to eq(2)
    expect(linha[:subtotal]).to eq(22)
    expect(linha[:total]).to eq(22)
  end

  it 'conta no mês pelo fuso de São Paulo (01/12 00:30 BRT ainda é dezembro)' do
    lead(reuniao_resultado: 'qualificada', reuniao_registrada_em: Time.zone.parse('2026-12-01 03:30:00 UTC'))

    expect(extrato_de(sdr)[:contagem]).to eq(0)
  end

  it 'Closer: R$22 por contrato limpo; bônus ao bater a meta e degrau a cada 20% (arredondado pra cima)', :aggregate_failures do
    MetaComercial.create!(account: account, user: closer, papel: 'closer', mes: mes, meta: 12)
    16.times { lead(contrato_limpo_em: em_novembro) }

    linha = extrato_de(closer)
    expect(linha[:subtotal]).to eq(352)
    expect(linha[:degraus]).to eq(1) # degrau = 3 (20% de 12 = 2,4 → 3); 16 - 12 = 4 → 1 degrau
    expect(linha[:bonus]).to eq(300)
    expect(linha[:total]).to eq(652)
  end

  it 'rampa garante o mínimo sobre as unidades e o bônus vem por cima', :aggregate_failures do
    MetaComercial.create!(account: account, user: sdr, papel: 'sdr', mes: mes, meta: 1, rampa: true)
    lead(reuniao_resultado: 'qualificada', reuniao_registrada_em: em_novembro)

    linha = extrato_de(sdr)
    expect(linha[:garantia_aplicada]).to be(true)
    expect(linha[:total]).to eq(300 + 150)
  end

  it 'respeita o teto mensal' do
    82.times { lead(contrato_limpo_em: em_novembro) } # 82 × R$22 = R$1.804

    expect(extrato_de(closer)[:total]).to eq(1800)
  end
end
