require 'rails_helper'

# Canal da cobrança (spec §7): dentro da janela de 24 h, o texto aprovado do passo; fora, só o modelo aprovado pela Meta
# (documentos_pendentes); sem ele, nada sai. Os textos esperados são os aprovados pelo Eduardo em 07/11, literais.
RSpec.describe Ramon::Documentos::Envio do
  let(:account) { create(:account) }
  let(:modelo) do
    { 'name' => 'documentos_pendentes', 'status' => 'APPROVED', 'category' => 'UTILITY', 'language' => 'pt_BR',
      'parameter_format' => 'POSITIONAL', 'components' => [{ 'type' => 'BODY', 'text' => 'Olá, {{1}}. ... ainda falta: {{2}}. ...' }] }
  end
  let(:modelos) { [modelo] }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: modelos).inbox
  end
  let(:conversa) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:tese) { create(:thesis, account: account) }
  let(:lead) { create(:lead, account: account, thesis: tese, conversation: conversa, name: 'Maria da Silva') }

  before do
    create(:thesis_item, thesis: tese, section: 'documento', title: 'RG', position: 1)
    create(:thesis_item, thesis: tese, section: 'documento', title: 'CNIS completo', position: 2)
  end

  def cliente_escreveu(atras)
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, created_at: atras.ago)
  end

  def enviadas = conversa.messages.outgoing

  context 'when a janela de 24 h está aberta' do
    before { cliente_escreveu(2.hours) }

    it 'abertura: o texto aprovado, com o nome e a lista do que falta, numa mensagem só', :aggregate_failures do
      expect(described_class.mandar(lead, :abertura)).to eq(:texto)
      expect(enviadas.count).to eq(1)
      expect(enviadas.last.content).to eq(<<~TEXTO.chomp)
        Oi, Maria! Aqui é da equipe do escritório Ramon Antonio, que bom ter você com a gente. Agora vamos juntar os documentos do seu caso, e eu te ajudo em cada passo. Falta isto:
        - RG
        - CNIS completo
        Por qual você quer começar? Se tiver qualquer dúvida no caminho, é só me chamar por aqui.
      TEXTO
      expect(enviadas.last.additional_attributes).not_to have_key('template_params')
    end

    it 'lembretes: o primeiro item que falta' do
      described_class.mandar(lead, :lembrete_1)
      described_class.mandar(lead, :lembrete_2)

      expect(enviadas.pluck(:content)).to eq([
                                               'Oi, Maria! Passando para lembrar do RG. Se tiver dificuldade para conseguir, me conta que ' \
                                               'eu te mostro o caminho.',
                                               'Bom dia, Maria! Ainda estou te esperando com o RG. Se preferir, alguém da nossa equipe pode ' \
                                               'te ligar para ajudar. É só me dizer.'
                                             ])
    end

    it 'encerramento (checklist completo): o texto aprovado, uma mensagem só' do
      expect(described_class.mandar(lead, :encerramento)).to eq(:texto)
      expect(enviadas.pluck(:content)).to eq(['Recebemos tudo, Maria! Muito obrigado pela paciência. Agora o seu caso segue para a ' \
                                              'nossa equipe jurídica, que vai estudar cada detalhe. Qualquer novidade, a gente te avisa ' \
                                              'por aqui.'])
    end
  end

  it 'texto vazio ou nil no yml desliga o passo: nada sai, nem modelo', :aggregate_failures do
    config = described_class::CONFIG
    stub_const("#{described_class}::CONFIG", config.merge('mensagens' => config['mensagens'].merge('lembrete_1' => nil, 'lembrete_2' => '')))
    cliente_escreveu(30.hours)

    expect(described_class.mandar(lead, :lembrete_1)).to eq(:desligado)
    expect(described_class.mandar(lead, :lembrete_2)).to eq(:desligado)
    expect(enviadas).to be_empty
  end

  context 'when a janela de 24 h fechou' do
    before { cliente_escreveu(30.hours) }

    it 'com o modelo aprovado na caixa: manda o modelo com nome e o que falta', :aggregate_failures do
      expect(described_class.mandar(lead, :lembrete_1)).to eq(:modelo)
      params = enviadas.last.additional_attributes['template_params']
      expect(params).to include('name' => 'documentos_pendentes', 'language' => 'pt_BR', 'category' => 'UTILITY')
      expect(params['processed_params']).to eq('body' => { '1' => 'Maria', '2' => 'RG e CNIS completo' })
      expect(enviadas.last.content).to eq('Olá, Maria. Para o seu caso seguir no escritório Ramon Antonio Advogados, ainda falta: RG e ' \
                                          'CNIS completo. Você pode enviar por aqui mesmo. Se precisar de ajuda, responda esta mensagem.')
    end

    it 'encerramento: o modelo de cobrança não serve, nada sai' do
      expect(described_class.mandar(lead, :encerramento)).to eq(:sem_permissao)
      expect(enviadas).to be_empty
    end

    context 'when a caixa não tem o modelo aprovado (antes do número oficial)' do
      let(:modelos) { [modelo.merge('status' => 'PENDING')] }

      it 'não manda nada' do
        expect(described_class.mandar(lead, :lembrete_1)).to eq(:sem_permissao)
        expect(enviadas).to be_empty
      end
    end
  end
end
