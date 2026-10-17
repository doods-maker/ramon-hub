require 'rails_helper'

RSpec.describe Ramon::PerfilIa do
  let(:account) { create(:account) }
  # etapas do seed (Leads::SeedDefaultConfigService) — Novo … Última chance, Fechado, Perdido
  let(:etapa) { ->(label) { account.lead_stages.find_by(label: label) } }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:tese) { create(:thesis, account: account) }

  def gravar(alvos) = account.update!(settings: { 'ia_atendimento' => alvos })

  it 'sem nada gravado vale o INICIAL (igual a hoje)' do
    perfil = described_class.de(conversa)
    expect([perfil.origem, perfil.alvo, perfil.marcador]).to eq([:padrao, 'padrao', '_inicio'])
    expect(perfil.permissao('logistica')).to eq(:sozinha)
    expect(perfil.permissao('citar_honorario')).to eq(:rascunho)
  end

  it 'quem manda: tese (própria ou o padrão) → caixa só sem tese → padrão' do
    gravar('padrao' => { 'base' => 'cautelosa' }, 'caixas' => { inbox.id.to_s => { 'base' => 'acelerada' } },
           'teses' => { tese.id.to_s => { 'base' => 'equilibrada' } })
    lead = create(:lead, account: account, conversation: conversa)
    expect(described_class.de(conversa).base).to eq('acelerada')
    lead.update!(thesis: tese)
    expect(described_class.de(conversa).alvo).to eq("tese:#{tese.id}")
    account.update!(settings: account.settings.deep_merge('ia_atendimento' => { 'teses' => { tese.id.to_s => nil } }))
    expect(described_class.de(conversa.reload).alvo).to eq('padrao') # tese que segue o padrão não cai na caixa
  end

  it 'estado da Etapa pelo Marcador; Fechado = :fechado; Perdido e Pausa = :pausada' do
    gravar('padrao' => { 'base' => 'equilibrada' }) # marcador depois de Reunião agendada
    perfil = described_class.de(conversa)
    expect(perfil.estado(etapa['fase-reuniao-agendada'])).to eq(:sozinha)
    expect(perfil.estado(etapa['fase-reuniao-realizada'])).to eq(:rascunho)
    expect(perfil.estado(account.lead_stages.find_by(is_won: true))).to eq(:fechado)
    expect(perfil.estado(account.lead_stages.find_by(is_lost: true))).to eq(:pausada)
    expect(perfil.estado(nil)).to eq(:sozinha) # sem lead/etapa = 1ª etapa aberta
    conversa.update!(custom_attributes: { 'ia_pausa' => 'pausada' })
    expect(described_class.de(conversa).estado(etapa['fase-novo'])).to eq(:pausada)
  end

  it 'lixo gravado cai na base; marcador desconhecido = _inicio' do
    gravar('padrao' => { 'base' => 'xablau', 'marcador' => 'fase-apagada', 'permissoes' => { 'logistica' => 'x' } })
    perfil = described_class.de(conversa)
    expect(perfil.base).to eq('cautelosa')
    expect(perfil.estado(etapa['fase-novo'])).to eq(:rascunho)
    expect(perfil.permissao('logistica')).to eq(:rascunho) # o da Cautelosa
  end

  it 'etapa sem label tem a chave "id-<id>" e serve de Marcador' do
    account.lead_stages.where('position >= 2').each { |s| s.update!(position: s.position + 1) }
    nova = create(:lead_stage, account: account, position: 2) # depois de Qualificação, sem label
    gravar('padrao' => { 'base' => 'cautelosa', 'marcador' => "id-#{nova.id}" })
    perfil = described_class.de(conversa)
    expect(described_class.chave_da_etapa(nova)).to eq("id-#{nova.id}")
    expect(perfil.estado(nova)).to eq(:sozinha)
    expect(perfil.estado(etapa['fase-reuniao-agendada'])).to eq(:rascunho)
  end

  it 'nunca tira as Tools da ação; direto? exige sozinha E Etapa antes do Marcador' do
    gravar('padrao' => { 'base' => 'cautelosa', 'marcador' => '_fim', 'permissoes' => { 'marcar_reuniao' => 's' } })
    lead = create(:lead, account: account, conversation: conversa, lead_stage: etapa['fase-qualificacao'])
    perfil = described_class.de(lead)
    expect(perfil.tools_bloqueadas).to contain_exactly('simular_honorario', 'preparar_contrato_zapsign')
    expect(perfil.direto?('marcar_reuniao')).to be(true)
    expect(perfil.direto?('mover_etapa')).to be(false)
  end

  describe '.decidir' do
    def d(perfil, **)
      described_class.decidir(perfil, etapa: etapa['fase-novo'], tools_usadas: [], logistica: nil, handoff: false,
                                      falhou: false, fora_do_horario: false, **)
    end
    let(:equilibrada) { gravar('padrao' => { 'base' => 'equilibrada' }) && described_class.de(conversa) }
    let(:inicial) { described_class.de(conversa) }

    it 'antes do Marcador sai; Tool de texto em rascunho segura a resposta toda' do
      expect(d(equilibrada)).to eq([:envia, 'antes_do_marcador'])
      expect(d(equilibrada, tools_usadas: ['simular_honorario'])).to eq([:rascunho, 'acao:citar_honorario'])
      expect(d(equilibrada, tools_usadas: ['mover_etapa'])).to eq([:envia, 'antes_do_marcador'])
    end

    it 'depois do Marcador: só logística, só com logistica sozinha, e Tool de texto é teto' do
      depois = etapa['fase-negociacao']
      expect(d(equilibrada, etapa: depois, logistica: true)).to eq([:envia, 'logistica'])
      expect(d(equilibrada, etapa: depois, logistica: nil)).to eq([:rascunho, 'depois_do_marcador'])
      expect(d(equilibrada, etapa: depois, logistica: true, tools_usadas: ['solicitar_documento']))
        .to eq([:rascunho, 'acao:pedir_documentos'])
    end

    it 'INICIAL = piloto limitado de hoje' do
      expect(d(inicial, logistica: true)).to eq([:envia, 'logistica'])
      expect(d(inicial, logistica: false)).to eq([:rascunho, 'depois_do_marcador'])
      expect(d(inicial, handoff: true, falhou: true)).to eq([:envia, 'handoff'])
      expect(d(inicial, logistica: true, fora_do_horario: true)).to eq([:envia, 'logistica'])
    end

    it 'pausa rascunho, Fechado, fora do horário em rascunho e falha de Tool viram rascunho' do
      conversa.update!(custom_attributes: { 'ia_pausa' => 'rascunho' })
      expect(d(described_class.de(conversa), handoff: true)).to eq([:rascunho, 'pausa'])
      conversa.update!(custom_attributes: {})
      expect(d(equilibrada, etapa: account.lead_stages.find_by(is_won: true))).to eq([:rascunho, 'fechado'])
      gravar('padrao' => { 'base' => 'cautelosa', 'marcador' => '_fim' })
      expect(d(described_class.de(conversa), fora_do_horario: true)).to eq([:rascunho, 'fora_do_horario'])
      expect(d(equilibrada, falhou: true)).to eq([:rascunho, 'ferramenta_falhou'])
    end
  end

  # O que o ResponseBuilderJob usa: a decisão do turno com a resposta do agente, o rastro e o carimbo.
  describe '#decidir_turno, #rastro e #carimbo' do
    before { gravar('padrao' => { 'base' => 'equilibrada' }) }

    it 'decide com a Etapa do início do turno, as Tools e a falha da resposta' do
      lead = create(:lead, account: account, conversation: conversa, lead_stage: etapa['fase-reuniao-agendada'])
      perfil = described_class.de(conversa)
      lead.update!(lead_stage: etapa['fase-negociacao']) # o lead anda durante o turno
      expect(perfil.decidir_turno({ 'response' => 'oi' }, logistica: nil, handoff: false)).to eq([:envia, 'antes_do_marcador'])
      expect(perfil.decidir_turno({ 'tools_usadas' => ['simular_honorario'] }, logistica: nil, handoff: false))
        .to eq([:rascunho, 'acao:citar_honorario'])
      expect(perfil.decidir_turno({ 'ferramenta_falhou' => true }, logistica: nil, handoff: false)).to eq([:rascunho, 'ferramenta_falhou'])
      expect(perfil.decidir_turno(nil, logistica: nil, handoff: true)).to eq([:envia, 'handoff'])
    end

    it 'rastro e carimbo dizem de qual perfil, alvo e Etapa veio a mensagem' do
      create(:lead, account: account, conversation: conversa, lead_stage: etapa['fase-qualificacao'])
      perfil = described_class.de(conversa)
      expect(perfil.rastro(nil)).to eq('alvo' => 'padrao', 'etapa' => 'fase-qualificacao', 'handoff' => false)
      expect(perfil.carimbo(true)['ramon_piloto']).to include('perfil' => 'Equilibrada', 'alvo' => 'padrao',
                                                              'etapa' => 'fase-qualificacao', 'handoff' => true, 'em' => kind_of(String))
    end
  end
end
