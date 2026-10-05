require 'rails_helper'

RSpec.describe Ramon::PortalAvisosJob do
  let(:novidade) do
    { 'tipo' => 'etapa', 'titulo' => 'Perícia agendada', 'o_que_esperar' => 'x', 'delicada' => false, 'vista' => false, 'avisada' => false }
  end
  let(:delicada) { novidade.merge('titulo' => 'Juiz deu a sentença', 'delicada' => true) }
  let!(:cliente) do
    create(:portal_cliente, convidado_em: 1.day.ago, email: 'maria@exemplo.com', telefone: '48999990000',
                            processos: [{ 'id' => 1, 'tipo' => 'AUXÍLIO-ACIDENTE (B94)', 'responsavel' => 'DRA X',
                                          'novidades' => [novidade, delicada] }])
  end
  let(:mail) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }
  let(:mailer) { double(novidade: mail, resumo_equipe: mail) } # rubocop:disable RSpec/VerifiedDoubles

  before { allow(Ramon::PortalMailer).to receive(:with).and_return(mailer) }

  it 'cliente suspenso não recebe aviso nem entra no resumo' do
    cliente.suspender!
    with_modified_env PORTAL_AVISOS: 'on' do
      described_class.perform_now
    end
    expect(Ramon::PortalMailer).not_to have_received(:with)
  end

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

  it "novidade com 'email' => false não vai por e-mail, mas entra no resumo da equipe" do
    sem_email = novidade.merge('titulo' => 'Conversa de boas-vindas', 'email' => false)
    cliente.update!(processos: [cliente.processos.first.merge('novidades' => [novidade.merge('email' => true), sem_email])])
    with_modified_env PORTAL_AVISOS: 'on' do
      described_class.perform_now
    end
    expect(Ramon::PortalMailer).to have_received(:with)
      .with(cliente: cliente, itens: [{ 'tipo' => 'auxílio-acidente', 'titulo' => 'Perícia agendada', 'o_que_esperar' => 'x' }])
    expect(Ramon::PortalMailer).to have_received(:with).with(hash_including(:linhas)) do |args|
      expect(args[:linhas].map { |l| [l['titulo'], l['email']] })
        .to eq([['Perícia agendada', 'Já recebeu por e-mail hoje.'], ['Conversa de boas-vindas', 'Não recebeu: etapa sem e-mail automático.']])
    end
  end

  it 'ligado e sem novidade pendente: não manda resumo' do
    cliente.update!(processos: [{ 'id' => 1, 'novidades' => [novidade.merge('avisada' => true)] }])
    with_modified_env PORTAL_AVISOS: 'on' do
      described_class.perform_now
    end
    expect(Ramon::PortalMailer).not_to have_received(:with)
  end
end
