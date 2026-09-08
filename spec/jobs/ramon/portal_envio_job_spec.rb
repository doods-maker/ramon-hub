require 'rails_helper'

RSpec.describe Ramon::PortalEnvioJob do
  let(:cliente) do
    create(:portal_cliente, nome: 'Maria de Lourdes', cpf: '12345678901',
                            processos: [{ 'id' => 14_039_119, 'numero' => '500', 'responsavel_id' => 259_713 }])
  end
  let(:envio) { create(:portal_envio, portal_cliente: cliente, lawsuit_id: 14_039_119, item: 'CNIS atualizado') }

  before do
    envio.arquivo.attach(io: File.open(Rails.root.join('spec/assets/sample.pdf')), filename: 'cnis.pdf', content_type: 'application/pdf')
    allow(Ramon::DriveClient).to receive_messages(configured?: true, root_id: 'root')
    allow(Ramon::DriveClient).to receive(:ensure_folder).with('Clientes', 'root').and_return('clientes')
    allow(Ramon::DriveClient).to receive(:ensure_folder).with('Maria de Lourdes — 12345678901', 'clientes').and_return('pasta')
    allow(Ramon::DriveClient).to receive(:upload).and_return('file-1')
    allow(Ramon::AdvboxClient).to receive(:create_post).and_return('posts_id' => 555)
  end

  it 'sobe pro Drive, abre a tarefa ANALISAR pro responsável e avisa' do
    expect { described_class.perform_now(envio.id) }.to have_enqueued_job(Ramon::NtfyPushJob)
    expect(envio.reload.drive_file_id).to eq 'file-1'
    expect(envio.advbox_post_id).to eq '555'
    expect(Ramon::AdvboxClient).to have_received(:create_post).with(
      hash_including(from: '259713', guests: [259_713], tasks_id: '9502039', lawsuits_id: '14039119')
    )
  end

  it 'é idempotente: não repete Drive nem ADVBOX' do
    envio.update!(drive_file_id: 'file-1', advbox_post_id: '555')
    described_class.perform_now(envio.id)
    expect(Ramon::DriveClient).not_to have_received(:upload)
    expect(Ramon::AdvboxClient).not_to have_received(:create_post)
  end
end
