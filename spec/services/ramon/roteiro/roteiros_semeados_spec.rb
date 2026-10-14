require 'rails_helper'

# Os roteiros aprovados (db/seeds/ramon/roteiros) rodando no motor de verdade: cada exemplo é um caminho do rascunho de
# 14/10 e confere, antes de cada resposta, que o motor pergunta exatamente aquele passo (os "vai para" levam ao lugar certo).
RSpec.describe 'Ramon::Roteiro (roteiros semeados)' do # rubocop:disable RSpec/DescribeClass -- Ramon::Roteiro explícito: described_class guarda o módulo antigo após reload
  let(:account) { create(:account) }
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:acidente) { 'Auxílio-acidente (B36)' }
  let(:bpc) { 'BPC/LOAS (idoso ou pessoa com deficiência)' }
  let(:maternidade) { 'Salário-maternidade' }

  before do
    travel_to Time.zone.local(2026, 10, 14, 12)
    Ramon::Roteiro::Seed.new(account).run
  end

  def lead_da(tese)
    create(:lead, account: account, thesis: account.theses.find_by!(name: tese), lead_stage: novo,
                  conversation: create(:conversation, account: account, status: :pending))
  end

  # Responde em ordem; cada par = [chave, valor, saida_id]. Devolve o resultado do último registro.
  def responder(lead, *pares)
    pares.map do |chave, valor, saida_id|
      expect(Ramon::Roteiro.atual(lead.reload)[:passo]&.chave).to eq(chave)
      Ramon::Roteiro.registrar(lead.reload, chave: chave, valor: valor, saida_id: saida_id)
    end.last
  end

  def comuns = [%w[nome Maria], %w[tem_advogado não]]

  it 'semeia 3 passos comuns e 17/10/12 nas teses; rodar de novo não cria nada' do
    contar = ->(nome) { RoteiroPasso.where(account: account, thesis: nome && account.theses.find_by!(name: nome)).count }

    expect([nil, acidente, bpc, maternidade].map(&contar)).to eq([3, 17, 10, 12])

    de_novo = Ramon::Roteiro::Seed.new(account).run
    expect(de_novo).to include(passos_atualizados: 42)
    expect(de_novo).not_to have_key(:passos_criados)
  end

  it 'auxílio-acidente: acidente de carteira, sem aposentadoria, com sequela e sem laudo → qualificado' do
    lead = lead_da(acidente)
    res = responder(lead, *comuns, %w[evento Acidente], %w[data_evento 15/03/2025], %w[auxilio_doenca não],
                    ['regime', 'Carteira assinada'], %w[aposentado não], ['sequela', 'dói o ombro e perdeu força', 'limitacao'],
                    ['ja_pediu_inss', 'Não pediu'], ['laudo', 'Não tem'])

    expect(res[:estado]).to include('desfecho' => 'qualificado')
    expect(res[:mensagem]).to include('vale a pena um advogado olhar')
    expect(lead.conversation.reload.label_list).to include('acidente', 'falta-laudo')
    expect(account.copilot_suggestions.pending.find_by!(lead: lead, kind: 'move_stage').payload)
      .to include('etapa_sugerida' => 'Qualificação')
  end

  # Review Focus 4 (D17).
  it 'auxílio-acidente: desempregado sem seguro-desemprego vai para a equipe, não para o Perdido' do
    lead = lead_da(acidente)
    res = responder(lead, *comuns, %w[evento Acidente], %w[data_evento 2025-03-15], %w[auxilio_doenca não],
                    %w[regime Desempregado], %w[teve_carteira_antes sim], %w[ultimo_vinculo 2023-10-15],
                    %w[mais_de_120 Não], %w[desemprego Não])

    expect(res[:estado]).to include('desfecho' => 'humano', 'motivo' => include('Súmula 27'))
    expect(account.copilot_suggestions.pending.where(lead: lead, kind: 'acao')).to be_empty
  end

  # Review Focus 4 (D10) e 3 (auxílio-doença pula o vínculo).
  it 'auxílio-acidente: autônomo sem carteira anterior → Perdido sugerido; com auxílio-doença pula o vínculo' do
    lead_autonomo = lead_da(acidente)
    autonomo = responder(lead_autonomo, *comuns, %w[evento Acidente], %w[data_evento 2025-03-15], %w[auxilio_doenca não],
                         ['regime', 'Autônomo ou MEI'], %w[autonomo_carteira_antes não])
    com_auxilio = responder(lead_da(acidente), *comuns, %w[evento Acidente], %w[data_evento 2025-03-15],
                            %w[auxilio_doenca sim], %w[aposentado sim], ['aposentadoria_quando', 'Antes do acidente'])

    expect(autonomo[:estado]).to include('desfecho' => 'desqualificado', 'aguarda_equipe' => true)
    expect(account.copilot_suggestions.pending.find_by!(lead: lead_autonomo, kind: 'acao').payload)
      .to include('lost_reason' => 'Sem viabilidade')
    expect(com_auxilio[:estado]).to include('desfecho' => 'desqualificado', 'motivo' => 'aposentado antes do acidente')
  end

  # Review Focus 3: idoso pula deficiência, duração e laudo.
  it 'BPC: idoso de 65+ vai direto aos moradores e qualifica com renda até 1/4 do salário mínimo' do
    lead = lead_da(bpc)
    res = responder(lead, *comuns, ['para_quem', 'Para a própria pessoa'], %w[recebe_beneficio não], %w[cadunico Não],
                    %w[nascimento 1955-05-10], %w[moradores 3], ['renda_total', 'R$ 1.200,00'])

    expect(res[:estado]).to include('desfecho' => 'qualificado')
    expect(res[:estado].dig('respostas', 'renda_total', 'calc')).to include('resultado' => 'abaixo')
    expect(lead.conversation.reload.label_list).to include('idoso')
  end

  it 'BPC: renda acima de 1/4 — com gasto de saúde vai para a equipe, sem gasto é desqualificado (D21)' do
    pares = [*comuns, ['para_quem', 'Para um familiar'], %w[recebe_beneficio não], ['cadunico', 'Sim, atualizado'],
             %w[nascimento 1955-05-10], %w[moradores 2], %w[renda_total 1621]]

    expect(responder(lead_da(bpc), *pares, %w[gastos_saude sim])[:estado]).to include('desfecho' => 'humano')
    expect(responder(lead_da(bpc), *pares, %w[gastos_saude não])[:estado]).to include('desfecho' => 'desqualificado')
  end

  # Review Focus 3: grávida não passa por "já recebeu"; a data do parto é a prevista pela conta (D28).
  it 'salário-maternidade: grávida que paga o INSS em dia e não pediu → qualificada' do
    res = responder(lead_da(maternidade), *comuns, ['para_quem', 'É a mãe'], %w[situacao Grávida], %w[semanas 30],
                    %w[data_parto 2026-12-23], ['trabalho', 'Paga o INSS por conta e está em dia'], ['ja_pediu_inss', 'Não pediu'])

    expect(res[:estado]).to include('desfecho' => 'qualificado')
    expect(res[:estado].dig('respostas', 'semanas', 'calc', 'detalhe')).to include('23/12/2026')
  end

  it 'salário-maternidade: desempregada fora do período de graça é desqualificada; rural vai para a equipe' do
    base = [*comuns, ['para_quem', 'É a mãe'], ['situacao', 'Bebê já nasceu'], %w[ja_recebeu não], %w[data_parto 15/06/2026]]
    fora = responder(lead_da(maternidade), *base, ['trabalho', 'Saiu do emprego e ficou desempregada'],
                     %w[ultima_contribuicao 2023-01-15])
    rural = responder(lead_da(maternidade), *base, ['trabalho', 'Trabalhadora rural ou pescadora'])

    expect(fora[:estado]).to include('desfecho' => 'desqualificado')
    expect(rural[:estado]).to include('desfecho' => 'humano', 'motivo' => include('rural'))
  end
end
