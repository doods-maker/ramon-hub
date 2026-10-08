require 'rails_helper'

RSpec.describe Ramon::Fluxos::Sistema do
  let(:account) { create(:account) }

  def sp(texto) = Time.find_zone!('America/Sao_Paulo').parse(texto)

  def do_sistema(chave) = account.fluxos.find_by(origem: 'sistema', sistema_chave: chave)

  it 'os 29 desenhos passam no Grafo (só a etapa fica em aberto: é do funil de cada conta)' do
    expect(described_class.desenhos.size).to eq(29)
    described_class.desenhos.each do |chave, d|
      erros = Ramon::Fluxos::Grafo.new(d['desenho']).erros.grep_v(/: falta etapa_id\z/)
      expect([chave, d['nome'].present?, d['grupo'].present?, erros]).to eq([chave, true, true, []])
    end
  end

  it 'cria 1 fluxo do sistema por desenho, desligado e sem versão, e não duplica' do
    2.times { described_class.sincronizar(account) }
    fluxos = account.fluxos.where(origem: 'sistema')
    expect(fluxos.pluck(:sistema_chave)).to match_array(described_class.desenhos.keys)
    expect(fluxos.pluck(:ativo, :versao_publicada_id).uniq).to eq([[false, nil]])
    expect(do_sistema('lembretes_reuniao')).to have_attributes(nome: 'Lembretes de reunião', gatilho_tipo: 'reuniao_marcada')
    expect(do_sistema('cadencia').limite_dia).to eq(15)
    expect(Fluxo.executaveis).to be_empty
  end

  it 'desenho corrigido no código chega à conta na próxima lista, sem criar outro' do
    described_class.sincronizar(account)
    novo = described_class.desenhos.deep_dup
    novo['cadencia']['nome'] = 'Cadência (corrigida)'
    allow(described_class).to receive(:desenhos).and_return(novo)
    expect { described_class.sincronizar(account) }.not_to(change { account.fluxos.count })
    expect(do_sistema('cadencia').nome).to eq('Cadência (corrigida)')
  end

  it 'nada mudou: não trava a conta' do
    described_class.sincronizar(account)
    allow(account).to receive(:with_lock)
    described_class.sincronizar(account)
    expect(account).not_to have_received(:with_lock)
  end

  it 'corrida: quem esperou o lock reencontra tudo em dia e não grava de novo' do
    allow(described_class).to receive(:em_dia?).and_return(false, true)
    expect { described_class.sincronizar(account) }.not_to(change { account.fluxos.count })
    expect(described_class.sincronizar(account)).to be_nil
  end

  it 'extras: grupo, selo de quem sai para fora e o rótulo do gatilho real' do
    expect(described_class.extras(account, 'avisos_painel')).to eq(
      hoje: nil, grupo: 'painel_cliente', alcance: 'fala_com_cliente',
      resumo: 'Todo dia às 8h, avisa o cliente por e-mail das novidades do caso (desligado até aprovarmos os textos).',
      gatilho_rotulo: 'Todo dia às 08:00 (só com PORTAL_AVISOS=on)', fixa: false
    )
    expect(described_class.extras(account, 'publicar_pecas')).to include(grupo: 'instagram', alcance: 'publica', hoje: 0)
    expect(described_class.extras(account, 'cadencia')).to include(alcance: nil, gatilho_rotulo: nil)
  end

  describe 'Hoje (fuso SP)' do
    let(:lead) { create(:lead, account: account) }
    let(:ganho) { account.lead_stages.find_by(is_won: true) }

    it 'toda fonte de "Hoje" é de um desenho e responde um número (coluna errada quebra aqui)' do
      expect(described_class::HOJE.keys - described_class.desenhos.keys).to eq([])
      expect(described_class::HOJE.keys.map { |c| described_class.hoje(account, c) }).to all(be_a(Integer))
    end

    it 'conta só onde há fonte barata; sem fonte fica sem número' do
      travel_to(sp('2026-10-06 10:00')) do
        lead.lead_notes.create!(account: account, body: "RASCUNHO (revisar antes de enviar) — retomada nº 1:\noi")
        lead.lead_notes.create!(account: account, body: 'outra nota')
        lead.lead_activities.create!(account: account, kind: 'meeting_scheduled', to_value: 'Reunião')
        lead.update_columns(docs_completos_em: Time.current, contrato_limpo_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
        AdvboxEvent.create!(account: account, event_key: 'e1', status: 'processed')
        AdvboxEvent.create!(account: account, event_key: 'e2', status: 'ignored')
        create(:lead, account: account, lead_stage: ganho)
        create(:conversation, account: account, inbox: create(:inbox, account: account, auto_create_lead: true))
        chaves = %w[cadencia lembretes_reuniao eventos_advbox lead_ganho sla_primeira_resposta docs_completos contrato_limpo resumo_do_dia]
        expect(chaves.map { |c| described_class.hoje(account, c) }).to eq([1, 1, 1, 1, 1, 1, 1, nil])
      end
    end

    it 'o dia é o de São Paulo' do
      travel_to(sp('2026-10-05 23:30')) { create(:lead, account: account, lead_stage: ganho) }
      travel_to(sp('2026-10-06 09:00')) { expect(described_class.hoje(account, 'lead_ganho')).to eq(0) }
    end
  end

  it 'as 5 regras de dado são "regra fixa" (ficam no código, decisão do Eduardo 07/10)' do
    account = create(:account)
    fixas = described_class.desenhos.keys.select { |chave| described_class.extras(account, chave)[:fixa] }
    expect(fixas).to eq(%w[contrato_limpo contrato_limpo_cancelado docs_completos historico_do_lead sdr_automatico])
  end
end
