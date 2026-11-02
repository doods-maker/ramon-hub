require 'rails_helper'
require 'prawn'

RSpec.describe Peticao do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  # CNJ válido com J=4 TR=04 (mesma fórmula do cnj_spec): DD = 98 - ((N + A + JTR + O + "00") % 97)
  def numero_valido_trf4
    dd = format('%02d', 98 - ('50012342026404720700'.to_i % 97))
    "5001234-#{dd}.2026.4.04.7207"
  end

  def nova(**attrs) = account.peticoes.new({ criado_por: user, responsavel: user, numero_processo: numero_valido_trf4 }.merge(attrs))

  it 'deduz o tribunal e normaliza o número' do
    p = nova(numero_processo: numero_valido_trf4.delete('^0-9'))
    p.valid?
    expect(p).to have_attributes(tribunal: 'trf4', numero_processo: numero_valido_trf4)
  end

  it 'recusa dígito errado' do
    expect(nova(numero_processo: '5001234-00.2026.4.04.7207')).not_to be_valid
  end

  it 'inicial dispensa número mas exige tribunal' do
    expect(nova(numero_processo: nil, inicial: true, tribunal: 'tjsc')).to be_valid
    expect(nova(numero_processo: nil, inicial: true)).not_to be_valid
  end

  it 'problemas: vazio, sem principal, acima do limite' do
    p = nova.tap(&:save!)
    expect(p.problemas).to eq(['sem_arquivos'])
    a = p.arquivos.create!(nome: 'Laudo.pdf', tipo: 'laudo_medico', posicao: 1, origem: 'upload', tamanho: 12 * 1024 * 1024)
    expect(p.reload.problemas).to eq(['sem_principal', "acima_do_limite:#{a.id}"])
  end

  it 'prazo_perto: sexta + 2 úteis = terça' do
    travel_to(Time.find_zone('America/Sao_Paulo').local(2026, 10, 30, 10)) do # sexta
      expect(nova(prazo: Date.new(2026, 11, 3)).prazo_perto?).to be(true)
      expect(nova(prazo: Date.new(2026, 11, 4)).prazo_perto?).to be(false)
    end
  end

  it 'registrar_protocolo! grava, enfileira o arquivamento e trava edição' do
    p = nova.tap(&:save!)
    p.arquivos.create!(nome: 'Peticao.pdf', tipo: 'peticao', posicao: 1, principal: true, origem: 'upload', tamanho: 10)
    comprovante = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')
    expect { p.registrar_protocolo!(usuario: user, numero_evento: '15', comprovante: comprovante) }
      .to have_enqueued_job(Ramon::PeticaoArquivarJob).with(p.id)
    expect(p.reload).to have_attributes(status: 'protocolada', numero_evento: '15', protocolada_por_id: user.id, editavel?: false)
    expect(p.comprovante).to be_attached
    expect do
      expect do
        p.registrar_protocolo!(usuario: user, numero_evento: '15', comprovante: nil)
      end.to raise_error(ActiveRecord::RecordInvalid, /já protocolada/)
    end.not_to have_enqueued_job(Ramon::PeticaoArquivarJob)
  end

  it 'registrar_protocolo! recusa pacote com problema' do
    p = nova.tap(&:save!)
    comprovante = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')
    expect { p.registrar_protocolo!(usuario: user, numero_evento: '1', comprovante: comprovante) }
      .to raise_error(ActiveRecord::RecordInvalid, /Pacote com problemas/)
  end

  it 'registrar_protocolo! recusa sem comprovante ou sem número do evento' do
    p = nova.tap(&:save!)
    p.arquivos.create!(nome: 'Peticao.pdf', tipo: 'peticao', posicao: 1, principal: true, origem: 'upload', tamanho: 10)
    comprovante = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')
    [[nil, '15'], ['', '15'], [comprovante, nil]].each do |arquivo, evento|
      expect { p.registrar_protocolo!(usuario: user, numero_evento: evento, comprovante: arquivo) }
        .to raise_error(ActiveRecord::RecordInvalid, /comprovante/)
    end
    expect(p.reload).to have_attributes(status: 'rascunho', protocolada_em: nil)
  end

  it 'número em branco vira nil (inicial)' do
    p = nova(numero_processo: '', inicial: true, tribunal: 'tjsc').tap(&:save!)
    expect(p.numero_processo).to be_nil
  end

  it 'mudanças no pacote entram no registro de ações da conta' do
    p = nova.tap(&:save!)
    arquivo = p.arquivos.create!(nome: 'Laudo.pdf', tipo: 'laudo_medico', posicao: 1, origem: 'upload', tamanho: 10)
    expect(arquivo.audits.last).to have_attributes(action: 'create', associated: account)
  end

  describe 'em conferência' do
    def em_conferencia(**attrs)
      account.peticoes.create!({ criado_por: user, responsavel: user, status: 'conferencia', pela_pasta: true, leitura: { 'estado' => 'lida' },
                                 drive_pasta_id: "p#{SecureRandom.hex(2)}" }.merge(attrs))
    end

    it 'dispensa tribunal e número' do
      expect(em_conferencia).to be_persisted
    end

    it 'não deixa a pasta ser usada em duas petições' do
      em_conferencia(drive_pasta_id: 'x')
      expect { em_conferencia(drive_pasta_id: 'x') }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'não registra protocolo' do
      p = em_conferencia(tribunal: 'trf4', numero_processo: numero_valido_trf4)
      arquivo = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')
      expect { p.registrar_protocolo!(usuario: user, numero_evento: '1', comprovante: arquivo) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    def com_pacote(peticao, bytes = nil)
      a = peticao.arquivos.create!(nome: 'A.pdf', tipo: 'peticao', posicao: 1, principal: true, origem: 'drive', tamanho: 4)
      a.file.attach(io: StringIO.new(bytes || Prawn::Document.new { text 'ok' }.render), filename: 'A.pdf', content_type: 'application/pdf')
      peticao
    end

    it 'confirmar! exige número e tribunal' do
      p = com_pacote(em_conferencia)
      expect { p.confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(p.errors[:tribunal]).to be_present
      expect(p.status).to eq('conferencia')
      expect(p.reload.status).to eq('conferencia')
    end

    it 'confirmar! com número e tribunal vira rascunho' do
      p = com_pacote(em_conferencia(tribunal: 'trf4', numero_processo: numero_valido_trf4))
      p.confirmar!
      expect(p.reload.status).to eq('rascunho')
    end

    it 'confirmar! trava com recusa, leitura em andamento ou com erro, e sem pacote' do
      dados = { tribunal: 'trf4', numero_processo: numero_valido_trf4 }
      { 'recusas' => ['sem_pdf'], 'estado' => 'lendo' }.each do |chave, valor|
        p = com_pacote(em_conferencia(**dados, leitura: { 'estado' => 'lida', chave => valor }))
        expect { p.confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
        expect(p.reload.status).to eq('conferencia')
      end
      expect { com_pacote(em_conferencia(**dados, leitura: { 'estado' => 'erro' })).confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
      expect { em_conferencia(**dados).confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'confirmar! só passa com a leitura lida: sem estado ou com estado desconhecido, trava' do
      dados = { tribunal: 'trf4', numero_processo: numero_valido_trf4 }
      [{}, { 'estado' => 'qualquer' }].each do |leitura|
        p = com_pacote(em_conferencia(**dados, leitura: leitura))
        expect { p.confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
        expect(p.reload.status).to eq('conferencia')
      end
    end

    it 'confirmar! trava com alerta não confirmado' do
      p = com_pacote(em_conferencia(tribunal: 'trf4', numero_processo: numero_valido_trf4,
                                    leitura: { 'estado' => 'lida', 'cpf_pasta' => '12345678909', 'campos' => { 'cpf' => '98765432100' } }))
      expect { p.confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
      p.confirmar!(confirmar_alertas: true)
      expect(p.reload.status).to eq('rascunho')
    end

    it 'confirmar! trava com marcador de rascunho na principal' do
      p = com_pacote(em_conferencia(tribunal: 'trf4', numero_processo: numero_valido_trf4), Prawn::Document.new { text '[CONFERIR] x' }.render)
      expect { p.confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(p.errors[:base]).not_to be_empty
    end

    it 'confirmar! não mexe em petição protocolada' do
      p = com_pacote(em_conferencia(tribunal: 'trf4', numero_processo: numero_valido_trf4))
      p.update_columns(status: 'protocolada') # rubocop:disable Rails/SkipsModelValidations
      expect { p.confirmar! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(p.reload.status).to eq('protocolada')
    end

    it 'problemas não acusa limite enquanto não há tribunal' do
      p = em_conferencia
      p.arquivos.create!(nome: 'A.pdf', tipo: 'peticao', posicao: 1, principal: true, origem: 'drive', tamanho: 12 * 1024 * 1024)
      expect(p.reload.problemas).to eq([])
    end

    it 'as_json_hub expõe pela_pasta e leitura' do
      expect(em_conferencia.as_json_hub).to include(pela_pasta: true, leitura: { 'estado' => 'lida' })
    end

    describe 'rascunho da pasta' do
      let(:comprovante) { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf') }
      let(:pdf_com_marcador) { Prawn::Document.new { text '[CPF] x' }.render }

      def rascunho_da_pasta(bytes = nil)
        com_pacote(em_conferencia(status: 'rascunho', tribunal: 'trf4', numero_processo: numero_valido_trf4), bytes)
      end

      it 'registrar_protocolo! recusa marcador de rascunho na principal' do
        p = rascunho_da_pasta(pdf_com_marcador)
        expect { p.registrar_protocolo!(usuario: user, numero_evento: '1', comprovante: comprovante) }
          .to raise_error(ActiveRecord::RecordInvalid, /sobra de rascunho/)
        expect(p.reload.status).to eq('rascunho')
      end

      it 'registrar_protocolo! não lê o PDF da petição manual' do
        p = com_pacote(nova.tap(&:save!), pdf_com_marcador)
        p.registrar_protocolo!(usuario: user, numero_evento: '1', comprovante: comprovante)
        expect(p.reload.status).to eq('protocolada')
      end

      it 'mudar o número volta a conferência, com o registro de ações, e confirmar! vale de novo' do
        p = rascunho_da_pasta
        dd = format('%02d', 98 - ('50099992026404720700'.to_i % 97))
        p.update!(numero_processo: "5009999-#{dd}.2026.4.04.7207")
        expect(p.reload.status).to eq('conferencia')
        expect(p.audits.reload.last.audited_changes).to include('status' => %w[rascunho conferencia])
        p.confirmar!
        expect(p.reload.status).to eq('rascunho')
      end

      it 'número inválido não vira conferência: a validação recusa' do
        p = rascunho_da_pasta
        expect { p.update!(numero_processo: '5001234-00.2026.4.04.7207') }.to raise_error(ActiveRecord::RecordInvalid)
        expect(p.reload.status).to eq('rascunho')
      end

      it 'mesmo número sem máscara, tribunal vazio e prazo não reabrem' do
        p = rascunho_da_pasta
        p.update!(numero_processo: numero_valido_trf4.delete('^0-9'), tribunal: '', prazo: Date.new(2026, 12, 1), descricao: 'Nova')
        expect(p.reload.status).to eq('rascunho')
      end

      it 'petição manual em rascunho não reabre' do
        p = nova.tap(&:save!)
        p.update!(contact: create(:contact, account: account))
        p.reabrir_conferencia!
        expect(p.reload.status).to eq('rascunho')
      end
    end
  end
end
