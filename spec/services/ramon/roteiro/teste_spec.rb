require 'rails_helper'

# Testar com tese (F2) pelo mesmo caminho do lead real (F5, revisão integrada item 11).
RSpec.describe 'Ramon::Roteiro::Teste' do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account) }
  let(:teste) { Ramon::Roteiro::Teste.de_params(account, { 'thesis_id' => thesis.id.to_s }) }

  def atual(teste) = Ramon::Roteiro::Teste.com_lead(account, teste) { |lead| Ramon::Roteiro.texto_atual(lead) }

  def registrar(teste, **resposta)
    Ramon::Roteiro::Teste.com_lead(account, teste) { |lead| Ramon::Roteiro.registrar(lead, **resposta) }
  end

  before do
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'recebeu', position: 0, titulo: 'Recebeu',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'humano', 'motivo' => 'recebeu' },
                                    { 'id' => 'nao', 'quando' => 'nao', 'acao' => 'seguir' }])
    create(:roteiro_passo, account: account, thesis: thesis, chave: 'renda', position: 1, titulo: 'Renda', tipo_resposta: 'numero')
  end

  it 'roda o motor de verdade, devolve o estado no teste e não grava nada' do
    expect(atual(teste)).to include('Passo atual: Recebeu')

    res = registrar(teste, chave: 'recebeu', valor: 'nao')
    expect(Ramon::Roteiro.resumo(res)).to include('Passo atual: Renda')
    expect(teste['estado'].dig('respostas', 'recebeu', 'valor')).to eq('nao')
    expect(atual(teste)).to include('Passo atual: Renda')
    expect([Lead.count, LeadActivity.count, CopilotSuggestion.count]).to eq([0, 0, 0])
  end

  it 'equipe no teste: desfecho no estado e no painel, sem sino e sem handoff (não há conversa)' do
    create(:user, account: account, role: :administrator)
    expect(registrar(teste, chave: 'recebeu', valor: 'sim')[:handoff]).to be(false)
    expect(teste['estado']).to include('desfecho' => 'humano', 'motivo' => 'recebeu')

    resposta = Ramon::Roteiro::Teste.resposta(account, teste)
    expect(resposta).to include('thesis_id' => thesis.id, 'estado' => teste['estado'])
    expect(resposta['painel']).to include('desfecho' => 'humano')
    expect([Notification.count, Lead.count]).to eq([0, 0])
  end

  it 'valor inválido volta o erro para a IA e o estado do teste não muda' do
    expect(registrar(teste, chave: 'recebeu', valor: 'talvez')).to eq(erro: 'Responda sim ou nao.')
    expect(teste['estado']).to be_nil
  end

  it 'de_params: tese da conta ou lead sem tese; tese de outra conta ou nada = sem teste; perfil da tela normalizado' do
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: create(:thesis, account: create(:account)).id })).to be_nil
    expect(Ramon::Roteiro::Teste.de_params(account, nil)).to be_nil
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: thesis.id, estado: { 'respostas' => {} } }))
      .to eq('thesis_id' => thesis.id, 'estado' => { 'respostas' => {} }, 'perfil' => nil)
    # o 'modo' que o front de hoje ainda manda é ignorado
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: '', modo: 'piloto_total' }))
      .to eq('thesis_id' => nil, 'estado' => nil, 'perfil' => nil)
    perfil = { 'base' => 'acelerada', 'permissoes' => { 'desqualificar' => 'x', 'mover_etapa' => 'n' }, 'xablau' => 1 }
    expect(Ramon::Roteiro::Teste.de_params(account, { thesis_id: thesis.id, perfil: perfil })['perfil'])
      .to eq('base' => 'acelerada', 'permissoes' => { 'mover_etapa' => 'n' }, 'gatilhos' => {})
  end

  # Revisão F5 item 9 + Review Focus 5: lead sem tese roda os comuns; a tese que o "assunto" escolhe volta no teste.
  it 'sem tese: o assunto escolhe a tese e as próximas mensagens seguem nela' do
    thesis.update!(palavras_chave: ['xablau'])
    create(:roteiro_passo, account: account, thesis: nil, chave: 'assunto', position: 0, titulo: 'Assunto', tipo_resposta: 'texto')
    sem_tese = Ramon::Roteiro::Teste.de_params(account, { thesis_id: '' })
    expect(atual(sem_tese)).to include('chave: assunto')

    registrar(sem_tese, chave: 'assunto', valor: 'quero saber do xablau')
    expect(sem_tese['thesis_id']).to eq(thesis.id)
    expect(atual(sem_tese)).to include('Passo atual: Recebeu')
    expect([Lead.count, thesis.leads.count]).to eq([0, 0])
  end

  it 'perfil simulado: Acelerada faz o Perdido na hora (sem aguardar a equipe); sem perfil vale o da tese, senão o padrão' do
    outra = create(:thesis, account: account)
    create(:roteiro_passo, account: account, thesis: outra, chave: 'advogado', position: 0, titulo: 'Advogado',
                           saidas: [{ 'id' => 'sim', 'quando' => 'sim', 'acao' => 'desqualificar', 'motivo' => 'tem advogado' }])
    direto = Ramon::Roteiro::Teste.de_params(account, { thesis_id: outra.id, perfil: { 'base' => 'acelerada' } })
    padrao = Ramon::Roteiro::Teste.de_params(account, { thesis_id: outra.id, modo: 'piloto_total' })

    registrar(direto, chave: 'advogado', valor: 'sim')
    registrar(padrao, chave: 'advogado', valor: 'sim')
    expect(direto['estado']).not_to have_key('aguarda_equipe')
    expect(padrao['estado']).to include('aguarda_equipe' => true) # INICIAL: desqualificar em rascunho = sugestão

    account.update!(settings: { 'ia_atendimento' => { 'teses' => { outra.id.to_s => { 'base' => 'acelerada' } } } })
    da_tese = Ramon::Roteiro::Teste.de_params(account, { thesis_id: outra.id })
    registrar(da_tese, chave: 'advogado', valor: 'sim')
    expect(da_tese['estado']).not_to have_key('aguarda_equipe')
    expect([Lead.count, CopilotSuggestion.count]).to eq([0, 0])
  end
end
