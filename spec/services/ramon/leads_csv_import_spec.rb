require 'rails_helper'

RSpec.describe Ramon::LeadsCsvImport do
  let(:account) { create(:account) }

  def run_import(csv)
    import = account.data_imports.new(data_type: 'leads')
    import.import_file.attach(io: StringIO.new(csv), filename: 'leads.csv', content_type: 'text/csv')
    import.save!(validate: false)
    described_class.new(import).perform
    import.reload
  end

  it 'cria pessoa nova com cpf normalizado, nascimento e sexo' do
    import = run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      Maria Silva,48 99999-0000,,529.982.247-25,15/03/1970,F,,,,,,,
    CSV
    contact = account.contacts.find_by(cpf: '52998224725')
    expect(contact.name).to eq('Maria Silva')
    expect(contact.phone_number).to eq('+5548999990000')
    expect(contact.data_nascimento).to eq(Date.new(1970, 3, 15))
    expect(contact.sexo).to eq('F')
    expect(import.status).to eq('completed')
    expect(account.leads.where(contact_id: contact.id)).to be_empty
  end

  it 'não dispara eventos por linha (lead/contact) e limpa o guard ao terminar' do
    account # materializa antes do spy — a criação da conta dispara eventos próprios
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      João,4899990001,,,,M,Auxílio-acidente,,,"1500,00",10/01/2024,,advbox
    CSV
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
    expect(Current.suppress_import_events).to be_nil
  end

  it 'faz match por cpf e só preenche campos vazios do contato' do
    existente = create(:contact, account: account, name: 'Maria', cpf: '52998224725')
    run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      Outro Nome,,,52998224725,1970-03-15,F,,,,,,,
    CSV
    existente.reload
    expect(existente.name).to eq('Maria')
    expect(existente.data_nascimento).to eq(Date.new(1970, 3, 15))
    expect(account.contacts.where(cpf: '52998224725').count).to eq(1)
  end

  it 'cria caso ganho com won_at na data do ganho' do
    run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      João,4899990001,,,,M,Auxílio-acidente,,,"1500,00",10/01/2024,,advbox
    CSV
    lead = account.leads.reorder(:id).last
    expect(lead.lead_stage.is_won).to be(true)
    expect(lead.won_at.to_date).to eq(Date.new(2024, 1, 10))
    expect(lead.benefit_type.name).to eq('Auxílio-acidente')
    expect(lead.value).to eq(1500)
    expect(lead.source).to eq('advbox')
    # import histórico não gera dossiê de passagem (handoff dispara só em update de won_at)
    expect(lead.lead_notes.where('body LIKE ?', '📋 DOSSIÊ%')).to be_empty
  end

  it 'cria caso aberto na primeira etapa quando etapa não informada' do
    run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      Ana,4899990002,,,,F,Auxílio-doença,,,,,,
    CSV
    lead = account.leads.reorder(:id).last
    expect(lead.lead_stage).to eq(account.lead_stages.order(:position).first)
    expect(lead.contact.phone_number).to eq('+554899990002')
  end

  it 'rejeita linha com benefício desconhecido e anexa failed_records' do
    import = run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      Zé,4899990003,,,,M,Benefício Inexistente,,,,,,
    CSV
    expect(account.leads.count).to eq(0)
    expect(import.processed_records).to eq(0)
    expect(import.total_records).to eq(1)
    expect(import.failed_records).to be_attached
  end

  it 'é idempotente: re-run não duplica pessoa nem caso' do
    csv = <<~CSV
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      João,4899990001,,,,M,Auxílio-acidente,,,,10/01/2024,,advbox
    CSV
    run_import(csv)
    expect { run_import(csv) }.not_to(change { [account.contacts.count, account.leads.count] })
  end

  it 'rejeita telefone inválido não-vazio' do
    import = run_import(<<~CSV)
      nome,telefone,email,cpf,data_nascimento,sexo,beneficio,tese,etapa,valor,ganho_em,canal,origem
      Bia,123,,,,F,,,,,,,
    CSV
    expect(import.processed_records).to eq(0)
    expect(import.failed_records).to be_attached
  end
end
