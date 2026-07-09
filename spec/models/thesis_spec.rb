require 'rails_helper'

RSpec.describe Thesis do
  let(:account) { create(:account) }

  it 'valida presença de nome' do
    thesis = account.theses.build(name: nil)
    expect(thesis).not_to be_valid
  end

  it 'valida nome único por conta' do
    account.theses.create!(name: 'Tese Custom', position: 50)
    dup = account.theses.build(name: 'Tese Custom', position: 51)
    expect(dup).not_to be_valid
  end

  it 'permite o mesmo nome em contas diferentes' do
    outra_conta = create(:account)
    account.theses.create!(name: 'Tese Compartilhada', position: 0)
    tese_outra_conta = outra_conta.theses.build(name: 'Tese Compartilhada', position: 0)
    expect(tese_outra_conta).to be_valid
  end

  it 'ordena por position (default_scope)' do
    primeira = account.theses.create!(name: 'Tese Topo', position: -1)
    expect(account.theses.first).to eq(primeira)
  end

  it 'destrói os thesis_items junto com a tese (dependent: :destroy)' do
    thesis = create(:thesis, account: account)
    item = create(:thesis_item, thesis: thesis)

    expect { thesis.destroy! }.to change(ThesisItem, :count).by(-1)
    expect(ThesisItem.find_by(id: item.id)).to be_nil
  end

  it 'anula thesis_id nos leads ao destruir a tese (dependent: :nullify)' do
    thesis = create(:thesis, account: account)
    lead = create(:lead, account: account, thesis: thesis)

    thesis.destroy!

    expect(lead.reload.thesis_id).to be_nil
  end

  it 'aceita honorário não configurado (nil)' do
    thesis = account.theses.build(
      name: 'Tese Sem Honorário',
      honorario_percentual: nil,
      honorario_n_mensalidades: nil
    )
    expect(thesis).to be_valid
  end

  it 'rejeita percentual de honorário fora de 0..100' do
    thesis = account.theses.build(name: 'Tese Percentual Ruim', honorario_percentual: 101)
    expect(thesis).not_to be_valid
  end

  it 'rejeita número de mensalidades negativo ou fracionário' do
    negativa = account.theses.build(name: 'Tese N Negativo', honorario_n_mensalidades: -1)
    fracionada = account.theses.build(name: 'Tese N Fracionário', honorario_n_mensalidades: 1.5)
    expect(negativa).not_to be_valid
    expect(fracionada).not_to be_valid
  end
end
