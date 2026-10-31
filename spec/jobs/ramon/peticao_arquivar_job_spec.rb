require 'rails_helper'

RSpec.describe Ramon::PeticaoArquivarJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:base) { nil }
  let(:peticao) do
    dd = format('%02d', 98 - ('50012342026404720700'.to_i % 97))
    account.peticoes.create!(criado_por: user, responsavel: user, numero_processo: "5001234-#{dd}.2026.4.04.7207",
                             status: 'protocolada', numero_evento: '15', protocolada_em: Time.zone.parse('2026-10-30 12:00'),
                             drive_pasta_base_id: base)
  end
  let(:arquivos) do
    [[1, 'Peticao.pdf', true], [2, 'Laudo.pdf', false]].map do |pos, nome, principal|
      peticao.arquivos.create!(nome: nome, tipo: principal ? 'peticao' : 'laudo_medico', posicao: pos, principal: principal,
                               origem: 'upload', tamanho: 4).tap do |a|
        a.file.attach(io: StringIO.new('%PDF'), filename: nome, content_type: 'application/pdf')
      end
    end
  end

  before do
    arquivos
    peticao.comprovante.attach(io: StringIO.new('%PDF'), filename: 'recibo.pdf', content_type: 'application/pdf')
    allow(Ramon::DriveClient).to receive_messages(configured?: true, root_id: 'raiz')
    allow(Ramon::DriveClient).to receive(:ensure_folder) { |nome, pai| "#{pai}/#{nome}" }
  end

  it 'sobe arquivos numerados e o comprovante, marca arquivada e apaga os arquivos locais' do
    ids = %w[f1 f2 c1].each
    allow(Ramon::DriveClient).to receive(:upload) { ids.next }
    described_class.perform_now(peticao.id)

    expect(Ramon::DriveClient).to have_received(:upload).with(hash_including(name: '01 Peticao.pdf')).once
    expect(Ramon::DriveClient).to have_received(:upload).with(hash_including(name: '02 Laudo.pdf')).once
    expect(Ramon::DriveClient).to have_received(:upload).with(hash_including(name: 'Comprovante — evento 15.pdf')).once
    expect(peticao.reload.arquivada_em).to be_present
    expect(peticao.arquivos.map(&:drive_file_id)).to eq(%w[f1 f2])
    expect(peticao.arquivos.map { |a| a.file.attached? }).to eq([false, false])
    expect(peticao.drive_pasta_id).to end_with("2026-10-30 — #{peticao.numero_processo} (##{peticao.id})")
  end

  it 'retry depois de falha no 2º arquivo não sobe o 1º de novo' do
    chamadas = 0
    allow(Ramon::DriveClient).to receive(:upload) do
      chamadas += 1
      raise 'drive fora' if chamadas == 2

      "id#{chamadas}"
    end
    described_class.perform_now(peticao.id) # retry_on engole o erro e reenfileira
    expect(peticao.reload.arquivada_em).to be_nil
    expect(peticao.arquivos.map(&:drive_file_id)).to eq(['id1', nil])
    expect(peticao.arquivos.map { |a| a.file.attached? }).to eq([true, true])

    nomes = []
    allow(Ramon::DriveClient).to receive(:upload) { |name:, **| (nomes << name) && "x#{nomes.size}" }
    described_class.perform_now(peticao.id)
    expect(nomes).to eq(['02 Laudo.pdf', 'Comprovante — evento 15.pdf'])
    expect(peticao.reload.arquivada_em).to be_present
  end

  context 'without pasta-base' do
    it 'usa "Protocolos sem cliente" na raiz' do
      allow(Ramon::DriveClient).to receive(:upload).and_return('f')
      described_class.perform_now(peticao.id)
      expect(Ramon::DriveClient).to have_received(:ensure_folder).with('Protocolos sem cliente', 'raiz')
      expect(Ramon::DriveClient).not_to have_received(:ensure_folder).with('Protocolos', anything)
    end
  end

  context 'with pasta-base' do
    let(:base) { 'base1' }

    it 'cria Protocolos dentro da base' do
      allow(Ramon::DriveClient).to receive(:upload).and_return('f')
      described_class.perform_now(peticao.id)
      expect(Ramon::DriveClient).to have_received(:ensure_folder).with('Protocolos', 'base1')
    end
  end

  it 'inicial: pasta "Inicial (#id)"' do
    peticao.update_columns(numero_processo: nil, inicial: true, tribunal: 'tjsc') # rubocop:disable Rails/SkipsModelValidations
    allow(Ramon::DriveClient).to receive(:upload).and_return('f')
    described_class.perform_now(peticao.id)
    expect(peticao.reload.drive_pasta_id).to end_with("2026-10-30 — Inicial (##{peticao.id})")
  end

  it 'não faz nada sem Drive configurado' do
    allow(Ramon::DriveClient).to receive(:configured?).and_return(false)
    allow(Ramon::DriveClient).to receive(:upload)
    described_class.perform_now(peticao.id)
    expect(Ramon::DriveClient).not_to have_received(:upload)
  end
end
