require 'rails_helper'

RSpec.describe Ramon::Peticionamento::AlertasDaPasta do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, cpf: '12345678909') }
  let(:numero) { '5001234-12.2026.4.04.7207' }
  let(:outro_numero) { '5009999-12.2026.4.04.7207' }

  def peticao(leitura: {}, contact: nil, numero_processo: nil)
    Peticao.new(account: account, contact: contact, numero_processo: numero_processo, leitura: leitura)
  end

  def peticao_do_contato = peticao(contact: contato, numero_processo: numero)

  def portal(processos:)
    PortalCliente.find_or_initialize_by(account: account, cpf: contato.cpf).tap do |p|
      p.assign_attributes(attributes_for(:portal_cliente).except(:cpf).merge(processos: processos))
      p.save!
    end
  end

  def alertas(peticao) = described_class.call(peticao)

  it 'CPF da peça diferente do CPF da pasta trava' do
    p = peticao(leitura: { 'cpf_pasta' => '11111111111', 'campos' => { 'cpf' => '22222222222' } })
    expect(alertas(p)[:alertas]).to eq(['cpf_diferente'])
  end

  it 'sem CPF de um dos lados, não trava' do
    expect(alertas(peticao(leitura: { 'cpf_pasta' => '11111111111', 'campos' => {} }))[:alertas]).to eq([])
  end

  it 'processo fora da lista do cliente trava; lista vazia só avisa' do
    portal(processos: [{ 'numero' => outro_numero }])
    expect(alertas(peticao_do_contato)[:alertas]).to eq(['processo_fora_do_cliente'])
    portal(processos: [])
    expect(alertas(peticao_do_contato)).to include(alertas: [], avisos: ['espelho_vazio'])
  end

  it 'processo na lista (número só com dígitos) não alerta' do
    portal(processos: [{ 'numero' => numero.delete('^0-9') }])
    expect(alertas(peticao_do_contato)).to eq(alertas: [], avisos: [])
  end

  it 'sem portal avisa espelho_vazio; sem contato ou número não confere' do
    expect(alertas(peticao_do_contato)).to eq(alertas: [], avisos: ['espelho_vazio'])
    expect(alertas(peticao(numero_processo: numero))).to eq(alertas: [], avisos: [])
  end

  it 'preserva os avisos gravados na leitura' do
    expect(alertas(peticao(leitura: { 'avisos' => ['sem_texto'] }))[:avisos]).to eq(['sem_texto'])
  end
end
