require 'rails_helper'

RSpec.describe Ramon::Hoje::Escritorio do
  let(:account) { create(:account) }
  let(:caixa) { create(:inbox, account: account, portaria_enabled: true) }
  let(:gabriela) { create(:user, account: account) }
  let(:tamires) { create(:user, account: account) }
  let(:agenda) { [] }

  before do
    allow(Ramon::AgendaHojeService).to receive(:new).and_return(instance_double(Ramon::AgendaHojeService, perform: agenda))
    allow(Ramon::SemanaAdvboxService).to receive(:new).and_return(instance_double(Ramon::SemanaAdvboxService, para: []))
  end

  def blocos(user, papel)
    described_class.new(account: account, user: user, papel: papel).perform
  end

  it 'recepção: sem responsável = sem agente e sem time na caixa do escritório' do
    livre = create(:conversation, account: account, inbox: caixa)
    create(:conversation, account: account, inbox: caixa, assignee: tamires)
    create(:conversation, account: account, assignee: tamires) # fora da caixa
    controladoria = create(:team, account: account, name: 'controladoria')
    create(:conversation, account: account, inbox: caixa, team: controladoria, assignee: gabriela)
    resultado = blocos(gabriela, 'recepcao')
    expect(resultado[:sem_responsavel].pluck(:conversa_id)).to eq([livre.display_id])
    expect(resultado[:caixa]).to eq(sem_responsavel: 1, controladoria: 1, com_advogadas: 1)
    expect(resultado[:advbox_fora]).to be(false)
  end

  it 'recepção: número de cliente do Painel vira cliente; o resto é número novo' do
    contato = create(:contact, account: account, phone_number: '+5547997110042')
    create(:portal_cliente, account: account, telefone: '4797110042') # cadastro antigo, sem o 9
    create(:conversation, account: account, inbox: caixa, contact: contato)
    create(:conversation, account: account, inbox: caixa)
    expect(blocos(gabriela, 'recepcao')[:sem_responsavel].pluck(:cliente)).to eq([true, false])
  end

  it 'variantes do telefone: com/sem 55 e com/sem o 9º dígito' do
    expect(described_class.variantes_telefone('+55 (47) 99711-0042'))
      .to contain_exactly('47997110042', '5547997110042', '4797110042', '554797110042')
    expect(described_class.variantes_telefone('4797110042')).to include('47997110042', '5547997110042')
    expect(described_class.variantes_telefone(nil)).to eq([])
  end

  context 'with atendimento do ADVBOX hoje' do
    let(:agenda) { [{ advbox_post_id: 5, cliente_nome: 'NEUSA', hora: '14:00' }, { advbox_post_id: 6, cliente_nome: 'ROBERTO', hora: '09:00' }] }

    it 'recepção: atendimentos em ordem de hora, com a situação da chegada' do
      account.chegadas.create!(criado_por: gabriela, destinatario: tamires, cliente_nome: 'Neusa', advbox_post_id: 5)
      atendimentos = blocos(gabriela, 'recepcao')[:atendimentos]
      expect(atendimentos.pluck(:cliente_nome)).to eq(%w[ROBERTO NEUSA])
      expect(atendimentos.pluck(:situacao)).to eq(%w[nao_chegou aguardando])
    end
  end

  it 'advogada: só as atribuídas a ela' do
    minha = create(:conversation, account: account, inbox: caixa, assignee: tamires)
    create(:conversation, account: account, inbox: caixa)
    resultado = blocos(tamires, 'advogada')
    expect(resultado[:atribuidas].pluck(:conversa_id)).to eq([minha.display_id])
    expect(resultado).to include(semana: [], advbox_fora: false)
  end

  it 'ADVBOX fora: avisa e segue' do
    allow(Ramon::SemanaAdvboxService).to receive(:new).and_raise(Ramon::AdvboxClient::UnavailableError)
    allow(Ramon::AgendaHojeService).to receive(:new).and_raise(Ramon::AdvboxClient::UnavailableError)
    create(:conversation, account: account, inbox: caixa)
    expect(blocos(tamires, 'advogada')).to include(semana: nil, advbox_fora: true)
    recepcao = blocos(gabriela, 'recepcao')
    expect(recepcao).to include(atendimentos: nil, advbox_fora: true)
    expect(recepcao[:sem_responsavel].size).to eq(1)
  end
end
