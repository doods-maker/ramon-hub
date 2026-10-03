require 'rails_helper'

RSpec.describe Ramon::GradeConteudo do
  let(:account) { create(:account) }
  let(:fuso) { Time.find_zone('America/Sao_Paulo') }

  it 'quarta 10h sugere quarta 12h' do
    expect(described_class.proximo_horario(account, fuso.local(2026, 10, 7, 10))).to eq fuso.local(2026, 10, 7, 12)
  end

  it 'pula slot ocupado' do
    create(:peca, account: account, status: 'agendado', agendado_para: fuso.local(2026, 10, 7, 12))
    expect(described_class.proximo_horario(account, fuso.local(2026, 10, 7, 10))).to eq fuso.local(2026, 10, 8, 12)
  end

  it 'sexta sugere a terça seguinte' do
    expect(described_class.proximo_horario(account, fuso.local(2026, 10, 9, 9))).to eq fuso.local(2026, 10, 13, 12)
  end

  it 'exatamente 12h já não serve' do
    expect(described_class.proximo_horario(account, fuso.local(2026, 10, 7, 12))).to eq fuso.local(2026, 10, 8, 12)
  end
end
