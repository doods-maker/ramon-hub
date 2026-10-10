require 'rails_helper'

RSpec.describe Ramon::PortalLembretes do
  let(:hoje) { Date.new(2027, 3, 2) }

  def cliente_com(agenda, fase: 'JUDICIAL')
    build(:portal_cliente, processos: [{ 'id' => 1, 'fase' => fase, 'agenda' => agenda }])
  end

  it 'audiência daqui a 7 dias: texto aprovado com dia da semana, hora, formato e WhatsApp; e-mail com saudação' do
    agenda = [{ 'tipo' => 'audiencia', 'quando' => '2027-03-09 16:00:00', 'formato' => 'presencial' }]
    _processo, lembrete = described_class.devidos(cliente_com(agenda), hoje: hoje).first
    expect(lembrete['titulo']).to eq 'Lembrete: sua audiência é no dia 09/03'
    expect(lembrete['texto']).to eq 'Olá, Maria. Sua audiência está marcada para terça-feira, 09/03/2027, às 16h (presencial). ' \
                                    'Nos próximos dias a nossa equipe vai falar com você para explicar como vai ser e como se preparar. ' \
                                    'Qualquer dúvida, fale com a gente pelo WhatsApp (48) 98855-4077.'
  end

  it 'perícia amanhã sem horário na tarefa: texto do dia anterior, sem saudação e sem "às"' do
    agenda = [{ 'tipo' => 'pericia', 'quando' => '2027-03-03 00:00:00' }]
    _processo, lembrete = described_class.devidos(cliente_com(agenda), hoje: hoje).first
    expect(lembrete['texto']).to eq 'Lembrete: sua perícia é amanhã, 03/03/2027. Chegue cedo e leve documento com foto, laudos, exames e receitas.'
  end

  it 'só 7 e 1 dia antes, e nunca de processo encerrado' do
    tres_dias = [{ 'tipo' => 'audiencia', 'quando' => '2027-03-05 10:00:00' }]
    expect(described_class.devidos(cliente_com(tres_dias), hoje: hoje)).to be_empty
    amanha = [{ 'tipo' => 'audiencia', 'quando' => '2027-03-03 09:30:00' }]
    expect(described_class.devidos(cliente_com(amanha, fase: 'ARQUIVAMENTO'), hoje: hoje)).to be_empty
    expect(described_class.devidos(cliente_com(amanha), hoje: hoje).first.last['corpo']).to include('amanhã, 03/03/2027, às 9h30.')
  end
end
