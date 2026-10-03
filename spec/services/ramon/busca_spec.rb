require 'rails_helper'

RSpec.describe Ramon::Busca do
  let(:account) { create(:account) }

  def busca(termo) = described_class.new(account, termo).perform

  it 'menos de 2 caracteres não busca' do
    expect(busca('j')).to eq(leads: [], clientes: [], processos: [])
  end

  it 'acha lead por nome sem acento, ignorando maiúsculas' do
    lead = create(:lead, account: account, name: 'João Pedro Martins')
    create(:lead, account: account, name: 'Maria das Dores')
    expect(busca('joao p')[:leads].pluck(:id)).to eq([lead.id])
    expect(busca('JOÃO')[:leads].pluck(:id)).to eq([lead.id])
  end

  it 'acha lead pelo telefone digitado com máscara' do
    contato = create(:contact, account: account, phone_number: '+5547996342210')
    lead = create(:lead, account: account, name: 'Sérgio Zanella', contact: contato)
    expect(busca('(47) 9 9634-2210')[:leads].first).to include(id: lead.id, nome: 'Sérgio Zanella', telefone: '+5547996342210')
  end

  it 'termo com letras não casa telefone pelos dígitos soltos' do
    contato = create(:contact, account: account, phone_number: '+5547996342210')
    create(:lead, account: account, name: 'Sérgio Zanella', contact: contato)
    expect(busca('ana 4799')[:leads]).to eq([])
  end

  it 'não devolve caso de cálculo (fora do funil)' do
    create(:lead, account: account, name: 'João Cálculo', source: Lead::FONTE_CALCULO)
    expect(busca('joao')[:leads]).to eq([])
  end

  it 'acha cliente do painel por nome sem acento e por CPF formatado' do
    cliente = create(:portal_cliente, account: account, nome: 'João Paulo Ramos', cpf: '12345678900',
                                      processos: [{ 'numero' => '1', 'responsavel' => 'Dra. Brenda', 'inicio' => '2022-03-01' }])
    expect(busca('joao paulo')[:clientes]).to eq([{ id: cliente.id, nome: 'João Paulo Ramos', advogada: 'Dra. Brenda', desde: '2022' }])
    expect(busca('123.456.789-00')[:clientes].pluck(:id)).to eq([cliente.id])
  end

  it 'acha processo pelo número com ou sem pontuação' do
    cliente = create(:portal_cliente, account: account, nome: 'João Paulo Ramos',
                                      processos: [{ 'numero' => '5001876-22.2023.4.04.7216', 'tipo' => 'Auxílio-doença' },
                                                  { 'numero' => '5009999-11.2024.4.04.7216', 'tipo' => 'BPC' }])
    esperado = [{ numero: '5001876-22.2023.4.04.7216', tipo: 'Auxílio-doença', cliente: 'João Paulo Ramos', cliente_id: cliente.id }]
    expect(busca('50018762220234047216')[:processos]).to eq(esperado)
    expect(busca('5001876-22.2023')[:processos]).to eq(esperado)
  end
end
