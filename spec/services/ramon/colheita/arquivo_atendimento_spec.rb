require 'rails_helper'

RSpec.describe Ramon::Colheita::ArquivoAtendimento do
  let(:account) { create(:account) }
  let(:tese) { create(:thesis, account: account, name: 'Tese Spec Atendimento') }
  let(:lead) { create(:lead, account: account, thesis: tese, name: 'Maria da Silva', docs_completos_em: 1.hour.ago) }
  let(:pasta) { 'pasta-tese-1' }
  let(:extracao) { instance_double(Ramon::ColheitaExtractionService, perform: nil) }

  def historico = lead.lead_activities.where(kind: 'documentos').pluck(:to_value)

  before do
    allow(Ramon::DriveClient).to receive_messages(configured?: true, conteudo_da_pasta: [], upload: 'file-1')
    allow(Ramon::DriveExportService).to receive(:new).and_return(instance_double(Ramon::DriveExportService, pasta_tese_id: pasta))
    allow(Ramon::ColheitaExtractionService).to receive(:new).with(lead).and_return(extracao)
  end

  it 'extrai, grava 00 Atendimento.md na pasta da tese e marca o lead', :aggregate_failures do
    expect(described_class.gravar(lead)).to eq(:gravado)

    expect(extracao).to have_received(:perform)
    expect(Ramon::DriveClient).to have_received(:upload)
      .with(name: '00 Atendimento.md', io: an_instance_of(StringIO), content_type: 'text/markdown', parent_id: pasta)
    marca = lead.reload.custom_attributes['atendimento_md']
    expect(marca).to include('file_id' => 'file-1', 'gravado_em' => be_present)
    expect(historico).to include('00 Atendimento.md gravado na pasta da tese')
  end

  it 'segunda chamada sem nova passagem: já gravado, nada sobe', :aggregate_failures do
    described_class.gravar(lead)

    expect(described_class.gravar(lead.reload)).to eq(:ja_gravado)
    expect(Ramon::DriveClient).to have_received(:upload).once
  end

  it 'passagem repetida com o arquivo já na pasta: sobe com a data no nome, sem sobrescrever', :aggregate_failures do
    described_class.gravar(lead)
    lead.update!(docs_completos_em: 1.minute.from_now)
    allow(Ramon::DriveClient).to receive(:conteudo_da_pasta).with(pasta).and_return([{ name: '00 Atendimento.md' }])

    expect(described_class.gravar(lead.reload)).to eq(:gravado)

    expect(Ramon::DriveClient).to have_received(:upload)
      .with(hash_including(name: "00 Atendimento (#{Time.current.strftime('%Y-%m-%d')}).md")).once
  end

  it 'Drive não configurado: :sem_drive, registra e não levanta', :aggregate_failures do
    allow(Ramon::DriveClient).to receive(:configured?).and_return(false)

    expect(described_class.gravar(lead)).to eq(:sem_drive)
    expect(Ramon::DriveClient).not_to have_received(:upload)
    expect(historico).to include('00 Atendimento.md: Drive não configurado')
  end

  it 'upload que levanta: :falhou, registra a classe do erro e não propaga', :aggregate_failures do
    allow(Ramon::DriveClient).to receive(:upload).and_raise(Errno::ECONNRESET)

    expect(described_class.gravar(lead)).to eq(:falhou)
    expect(historico).to include(a_string_including('00 Atendimento.md não foi gravado: Errno::ECONNRESET'))
    expect(lead.reload.custom_attributes['atendimento_md']).to be_nil
  end

  it 'erro transitório da extração: grava com a colheita que já existe' do
    allow(extracao).to receive(:perform).and_raise(Ramon::LlmClient::TransientError)

    expect(described_class.gravar(lead)).to eq(:gravado)
  end
end
