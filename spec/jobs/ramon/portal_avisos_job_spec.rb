require 'rails_helper'

RSpec.describe Ramon::PortalAvisosJob do
  let(:novidade) { { 'tipo' => 'etapa', 'titulo' => 'Perícia agendada', 'o_que_esperar' => 'x', 'delicada' => false, 'vista' => false, 'avisada' => false } }
  let(:delicada) { novidade.merge('titulo' => 'Juiz deu a sentença', 'delicada' => true) }
  let!(:cliente) do
    create(:portal_cliente, convidado_em: 1.day.ago, email: 'maria@exemplo.com', telefone: '48999990000',
                            processos: [{ 'id' => 1, 'tipo' => 'AUXÍLIO-ACIDENTE (B94)', 'responsavel' => 'DRA X',
                                          'novidades' => [novidade, delicada] }])
  end
  let(:mail) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }
  let(:mailer) { double(novidade: mail, resumo_equipe: mail) } # rubocop:disable RSpec/VerifiedDoubles

  before { allow(Ramon::PortalMailer).to receive(:with).and_return(mailer) }

  it 'desligado (sem PORTAL_AVISOS=on) não envia nada' do
    described_class.perform_now
    expect(Ramon::PortalMailer).not_to have_received(:with)
  end

  it 'ligado: e-mail ao cliente só com a novidade comum, resumo da equipe com as duas e wa.me; marca avisadas' do
    with_modified_env PORTAL_AVISOS: 'on' do
      described_class.perform_now
    end
    expect(Ramon::PortalMailer).to have_received(:with)
      .with(cliente: cliente, itens: [{ 'tipo' => 'auxílio-acidente', 'titulo' => 'Perícia agendada', 'o_que_esperar' => 'x' }])
    expect(Ramon::PortalMailer).to have_received(:with).with(hash_including(para: 'ramonantonio.comercial@gmail.com')) do |args|
      expect(args[:linhas].map { |l| [l['titulo'], l['delicada']] }).to eq([['Perícia agendada', false], ['Juiz deu a sentença', true]])
      expect(args[:linhas].first['link_wa']).to start_with('https://wa.me/5548999990000?text=')
    end
    expect(cliente.reload.processos.first['novidades'].pluck('avisada')).to all(be true)
  end

  it 'ligado e sem novidade pendente: não manda resumo' do
    cliente.update!(processos: [{ 'id' => 1, 'novidades' => [novidade.merge('avisada' => true)] }])
    with_modified_env PORTAL_AVISOS: 'on' do
      described_class.perform_now
    end
    expect(Ramon::PortalMailer).not_to have_received(:with)
  end
end
