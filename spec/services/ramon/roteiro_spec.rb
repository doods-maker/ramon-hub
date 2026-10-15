require 'rails_helper'

# rubocop:disable RSpec/DescribedClass -- constante explícita: no CI a recarga de código deixa o described_class velho (lição F5)
RSpec.describe Ramon::Roteiro do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  # Toda conta nasce com o funil e os motivos de perda padrão (Leads::SeedDefaultConfigService).
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:qualificacao) { account.lead_stages.find_by!(name: 'Qualificação') }
  let(:perdido) { account.lead_stages.find_by!(is_lost: true) }
  let(:conversation) { create(:conversation, account: account, status: :pending) }
  let(:lead) { create(:lead, account: account, thesis: thesis, lead_stage: novo, conversation: conversation) }

  def passo(chave, position, **attrs)
    create(:roteiro_passo, account: account, thesis: thesis, chave: chave, position: position, titulo: chave.humanize, **attrs)
  end

  def registrar(chave, valor = nil, saida_id: nil)
    Ramon::Roteiro.registrar(lead.reload, chave: chave, valor: valor, saida_id: saida_id)
  end

  def piloto_total!
    conversation.update!(custom_attributes: { 'copiloto_modo' => 'piloto_total' })
  end

  before do
    create(:roteiro_passo, account: account, thesis: nil, chave: 'tem_advogado', position: 0, titulo: 'Tem advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado',
                                      'motivo_perda' => 'Outro', 'mensagem' => 'Que bom que ja tem quem cuide.',
                                      'efeitos' => { 'etiqueta' => 'TemAdvogado' } },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    passo('recebeu_auxilio', 1, saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'ir_para', 'alvo' => 'sequela' },
                                         { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    passo('data_acidente', 2, tipo_resposta: 'data')
    passo('graca', 3, tipo_resposta: 'data', calculadora: 'periodo_de_graca',
                      calculadora_campos: { 'ultimo_vinculo' => 'graca', 'evento' => 'data_acidente' },
                      saidas: [{ 'id' => 'dentro', 'quando' => 'dentro', 'acao' => 'seguir' },
                               { 'id' => 'fora', 'quando' => 'fora', 'acao' => 'desqualificar', 'motivo' => 'fora do periodo de graca' },
                               { 'id' => 'outro', 'quando' => '*', 'acao' => 'humano', 'motivo' => 'graca depende' }])
    passo('sequela', 4, tipo_resposta: 'texto',
                        saidas: [{ 'id' => 'ficou', 'quando' => 'ficou alguma limitacao', 'acao' => 'concluir',
                                   'efeitos' => { 'etapa' => 'Qualificação' } },
                                 { 'id' => 'voltou_100', 'quando' => 'voltou 100%', 'acao' => 'desqualificar', 'motivo' => 'sem sequela' }])
  end

  it 'lead sem tese fica sem roteiro (tese automática = F3)' do
    sem_tese = create(:lead, account: account, lead_stage: novo)
    expect(Ramon::Roteiro.atual(sem_tese)).to be_nil
    expect(Ramon::Roteiro.registrar(sem_tese, chave: 'tem_advogado', valor: 'nao')).to eq(erro: 'Este caso nao tem roteiro.')
  end

  it 'tese sem passos próprios roda os comuns e devolve para a triagem de sempre' do
    outro = create(:lead, account: account, thesis: create(:thesis, account: account), lead_stage: novo)
    expect(Ramon::Roteiro.atual(outro)[:passo].chave).to eq('tem_advogado')

    res = Ramon::Roteiro.registrar(outro, chave: 'tem_advogado', valor: 'nao')
    expect(res[:proximo]).to be_nil
    expect(res[:estado]['desfecho']).to be_nil
    expect(Ramon::Roteiro.resumo(res)).to include('siga a triagem de sempre')
  end

  it 'grava no estado o próximo passo a perguntar (bi_roteiro) e o limpa no desfecho' do
    expect(registrar('tem_advogado', 'nao')[:estado]['passo']).to eq('recebeu_auxilio')
    expect(registrar('recebeu_auxilio', 'sim')[:estado]['passo']).to eq('sequela')
    expect(lead.reload.custom_attributes.dig('roteiro', 'passo')).to eq('sequela')

    registrar('sequela', 'dor no punho', saida_id: 'ficou')
    expect(lead.reload.custom_attributes['roteiro']).to include('passo' => nil, 'desfecho' => 'qualificado')
  end

  it 'começa pelos comuns e segue a ordem' do
    expect(Ramon::Roteiro.atual(lead)[:passo].chave).to eq('tem_advogado')
    expect(registrar('tem_advogado', 'Não')[:proximo].chave).to eq('recebeu_auxilio')
    expect(lead.reload.custom_attributes.dig('roteiro', 'respostas', 'tem_advogado', 'valor')).to eq('nao')
  end

  it 'ir_para pula etapas; concluir qualifica e, fora do piloto total, sugere a etapa no Cockpit' do
    registrar('tem_advogado', 'nao')
    expect(registrar('recebeu_auxilio', 'sim')[:proximo].chave).to eq('sequela')

    res = registrar('sequela', 'ficou com dor no punho', saida_id: 'ficou')
    expect(res[:estado]).to include('desfecho' => 'qualificado', 'decisivo' => 'sequela')
    expect(res[:proximo]).to be_nil
    expect(lead.reload.lead_stage).to eq(novo)
    sugestao = account.copilot_suggestions.pending.find_by!(lead: lead, kind: 'move_stage')
    expect(sugestao.payload).to include('etapa_sugerida' => 'Qualificação', 'origem' => 'roteiro')
    expect(lead.lead_activities.where(kind: 'roteiro').last.to_value).to eq('Sequela → qualificado')
  end

  it 'em piloto total a etapa muda direto' do
    piloto_total!
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim')
    registrar('sequela', 'ficou com dor no punho', saida_id: 'ficou')
    expect(lead.reload.lead_stage).to eq(qualificacao)
    expect(account.copilot_suggestions.count).to eq(0)
  end

  it 'a calculadora decide; fora do piloto total o Perdido vira sugestão e a IA não é calada' do
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'nao')
    registrar('data_acidente', '10/01/2026')
    res = registrar('graca', '2022-01-01') # 36 meses mantêm só até 15/03/2025

    expect(res[:calc][:resultado]).to eq('fora')
    expect(res[:estado]).to include('desfecho' => 'desqualificado', 'motivo' => 'fora do periodo de graca',
                                    'decisivo' => 'graca', 'aguarda_equipe' => true)
    expect(lead.reload.lead_stage).to eq(novo)
    sugestao = account.copilot_suggestions.pending.find_by!(lead: lead, kind: 'acao')
    expect(sugestao.payload).to include('acao' => 'perdido', 'lost_reason' => 'Sem viabilidade', 'origem' => 'roteiro')
    expect(conversation.reload.label_list).not_to include('desqualificado-ia')
    expect(conversation.custom_attributes['copiloto_modo']).to be_nil
    expect(Ramon::Roteiro.descrever(nil, res[:estado])).to include('aguardando a equipe')
  end

  it 'em piloto total desqualifica direto: motivo do catálogo, etiquetas e IA calada com o robô, guardando o modo' do
    piloto_total!
    res = registrar('tem_advogado', 'sim')

    expect(res[:mensagem]).to eq('Que bom que ja tem quem cuide.')
    expect(res[:estado]).not_to have_key('aguarda_equipe')
    expect(lead.reload).to have_attributes(lead_stage: perdido, lost_reason: 'Outro')
    expect(conversation.reload.label_list).to include('temadvogado', 'desqualificado-ia')
    expect(conversation.custom_attributes).to include('copiloto_modo' => 'manual', 'copiloto_modo_antes_roteiro' => 'piloto_total')
    expect(conversation.status).to eq('pending')
  end

  it 'a etiqueta da saída vale em qualquer modo' do
    registrar('tem_advogado', 'sim')
    expect(conversation.reload.label_list).to include('temadvogado')
    expect(conversation.label_list).not_to include('desqualificado-ia')
  end

  it 'resposta adiantada não é perguntada de novo nem pula o passo atual' do
    registrar('data_acidente', '10/01/2026')
    expect(Ramon::Roteiro.atual(lead.reload)[:passo].chave).to eq('tem_advogado')

    registrar('tem_advogado', 'nao')
    expect(registrar('recebeu_auxilio', 'nao')[:proximo].chave).to eq('graca')
  end

  it 'corrigir um passo já respondido vale a nova resposta e volta a seguir dali' do
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim') # pulou para sequela
    res = registrar('recebeu_auxilio', 'nao')

    expect(res[:proximo].chave).to eq('data_acidente')
    expect(res[:estado].dig('respostas', 'recebeu_auxilio', 'valor')).to eq('nao')
  end

  it 'corrigir uma resposta adiantada não pula os passos anteriores' do
    registrar('data_acidente', '10/01/2026')
    registrar('data_acidente', '11/01/2026')
    expect(Ramon::Roteiro.atual(lead.reload)[:passo].chave).to eq('tem_advogado')
  end

  it 'nada casando vai para a equipe com sino ao gestor' do
    admin = create(:user, account: account, role: :administrator)
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim')
    res = registrar('sequela', 'nao sei dizer')

    expect(res[:estado]['desfecho']).to eq('humano')
    expect(res[:estado]['motivo']).to include('roteiro sem saida no passo sequela')
    expect(conversation.reload.status).to eq('open')
    expect(conversation.custom_attributes['copiloto_modo']).to eq('rascunho')
    expect(Notification.where(user: admin, primary_actor: lead, notification_type: 'ramon_fluxo_aviso').count).to eq(1)
  end

  # Spec §5: roteiro sem saída = configuração quebrada → além do responsável, os administradores ficam sabendo.
  it 'roteiro sem saída avisa o SDR do lead e também os administradores' do
    admin = create(:user, account: account, role: :administrator)
    sdr = create(:user, account: account, role: :agent)
    lead.update_columns(sdr_id: sdr.id) # rubocop:disable Rails/SkipsModelValidations -- sem atribuir a conversa
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim')
    registrar('sequela', 'nao sei dizer')

    avisados = Notification.where(primary_actor: lead, notification_type: 'ramon_fluxo_aviso').pluck(:user_id)
    expect(avisados).to contain_exactly(sdr.id, admin.id)
  end

  # Revisão F5 item 12: o handoff do roteiro é um sinal no resultado (a tool o põe no state), não um texto.
  it 'o resultado sinaliza handoff só quando o roteiro acabou de passar para a equipe com conversa' do
    expect(registrar('tem_advogado', 'nao')[:handoff]).to be(false)
    registrar('recebeu_auxilio', 'sim')
    expect(registrar('sequela', 'nao sei dizer')[:handoff]).to be(true)

    sem_conversa = create(:lead, account: account, thesis: thesis, lead_stage: novo)
    Ramon::Roteiro.registrar(sem_conversa, chave: 'tem_advogado', valor: 'nao')
    Ramon::Roteiro.registrar(sem_conversa.reload, chave: 'recebeu_auxilio', valor: 'sim')
    expect(Ramon::Roteiro.registrar(sem_conversa.reload, chave: 'sequela', valor: 'nao sei')[:handoff]).to be(false)
  end

  it 'ir_para para passo inexistente vai para a equipe' do
    RoteiroPasso.find_by(chave: 'recebeu_auxilio').update!(saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'ir_para', 'alvo' => 'sumiu' }])
    registrar('tem_advogado', 'nao')
    expect(registrar('recebeu_auxilio', 'sim')[:estado]['motivo']).to include('destino sumiu nao existe')
  end

  it 'valor inválido não grava nada' do
    expect(registrar('tem_advogado', 'talvez')).to eq(erro: 'Responda sim ou nao.')
    expect(registrar('data_acidente', '31/02/2026')[:erro]).to include('AAAA-MM-DD')
    expect(registrar('sequela')[:erro]).to include('saida_id')
    expect(registrar('sequela', 'x', saida_id: 'nao_tem')[:erro]).to include('nao existe')
    expect(registrar('xablau', 'sim')[:erro]).to include('tem_advogado, recebeu_auxilio')
    expect(lead.reload.custom_attributes['roteiro']).to be_nil
  end

  # Spec §5: erro no meio do registro desfaz tudo e sobe para a tool — o BasePublicTool marca o turno (falhou) e a
  # resposta vira rascunho.
  it 'erro nos efeitos desfaz o registro inteiro e sobe a exceção' do
    allow(Ramon::Roteiro::Efeitos).to receive(:aplicar).and_raise(RuntimeError, 'boom')

    expect { registrar('tem_advogado', 'sim') }.to raise_error('boom')
    expect(lead.reload.custom_attributes['roteiro']).to be_nil
  end

  it 'depois do desfecho recusa (inclusive correção) e não mexe em nada' do
    registrar('tem_advogado', 'sim')
    expect(registrar('recebeu_auxilio', 'nao')[:erro]).to include('ja terminou')
    expect(registrar('tem_advogado', 'nao')[:erro]).to include('ja terminou')
    expect(lead.reload.custom_attributes.dig('roteiro', 'respostas')).to match('tem_advogado' => a_hash_including('valor' => 'sim'))
  end

  it 'lead ganho não volta para Perdido nem vira sugestão' do
    ganho = account.lead_stages.find_by!(is_won: true)
    lead.update_columns(lead_stage_id: ganho.id, won_at: Time.current) # rubocop:disable Rails/SkipsModelValidations -- sem disparar o fluxo "Lead ganho"
    registrar('tem_advogado', 'sim')
    expect(lead.reload.lead_stage).to eq(ganho)
    expect(account.copilot_suggestions.count).to eq(0)
    expect(lead.custom_attributes.dig('roteiro', 'aguarda_equipe')).to be_nil
  end

  it 'trocar a tese recomeça o roteiro e mantém os comuns' do
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'nao')
    bpc = create(:thesis, account: account)
    create(:roteiro_passo, account: account, thesis: bpc, chave: 'renda', position: 1)
    lead.update!(thesis: bpc)

    atual = Ramon::Roteiro.atual(lead.reload)
    expect(atual[:passo].chave).to eq('renda')
    expect(atual[:estado]['respostas'].keys).to eq(['tem_advogado'])
  end

  it 'trocar a tese depois de desqualificar num comum pergunta o comum de novo' do
    registrar('tem_advogado', 'sim')
    lead.update!(thesis: create(:thesis, account: account))
    expect(Ramon::Roteiro.atual(lead.reload)[:passo].chave).to eq('tem_advogado')
  end

  # Revisão F5 item 5: o estado gravado zera na troca (o limite dos modos e a bi_roteiro leem o atributo cru).
  it 'trocar a tese depois do desfecho zera o roteiro gravado na hora, mantendo os comuns' do
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim')
    registrar('sequela', 'ficou', saida_id: 'ficou')
    expect(lead.reload.desfecho_roteiro).to eq('qualificado')

    bpc = create(:thesis, account: account)
    create(:roteiro_passo, account: account, thesis: bpc, chave: 'renda', position: 1)
    lead.update!(thesis: bpc)

    salvo = lead.reload.custom_attributes['roteiro']
    expect(salvo).to include('tese_id' => bpc.id, 'passo' => 'renda')
    expect(salvo.keys).not_to include('desfecho', 'motivo', 'decisivo')
    expect(salvo['respostas'].keys).to eq(['tem_advogado'])
  end

  it 'descrever mostra o passo, as saídas do texto e o que já foi respondido' do
    registrar('tem_advogado', 'nao')
    registrar('recebeu_auxilio', 'sim')
    texto = Ramon::Roteiro.descrever(*Ramon::Roteiro.atual(lead.reload).values_at(:passo, :estado))
    expect(texto).to include('Passo atual: Sequela (chave: sequela')
      .and include('ficou = ficou alguma limitacao').and include('tem_advogado=nao')
    expect(Ramon::Roteiro.texto_atual(lead.reload)).to eq(texto)
    expect(Ramon::Roteiro.descrever(nil, { 'desfecho' => 'humano', 'motivo' => 'x', 'respostas' => {} }))
      .to include('Roteiro encerrado: humano (x)')
  end
end
# rubocop:enable RSpec/DescribedClass
