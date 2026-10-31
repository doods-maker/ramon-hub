require 'rails_helper'

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
end
