require 'rails_helper'

RSpec.describe Ramon::FunilObservador::Aplicar do
  let(:account) { create(:account) }
  let(:etapa) { 'fase-novo' }
  let(:conversa) { create(:conversation, account: account, status: :pending) }
  let(:lead) { create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: etapa), conversation: conversa) }

  def ligar(peca, modo = 'on') = Ramon::FunilAutomatico.mudar!(account, peca, modo)

  def aplicar(decisao) = described_class.new(lead, decisao).perform

  describe 'etapa' do
    before { ligar('etapa_ia') }

    it 'qualificacao leva Novo a Qualificação' do
      aplicar('etapa' => 'qualificacao', 'etapa_motivo' => 'respondeu as perguntas')

      expect(lead.reload.lead_stage.label).to eq('fase-qualificacao')
      expect(FunilAcao.last).to have_attributes(peca: 'etapa_ia', acao: 'mover_etapa', motivo: 'respondeu as perguntas')
    end

    it 'qualificacao com o lead em Negociação não faz nada' do
      lead.update!(lead_stage: account.lead_stages.find_by(label: 'fase-negociacao'))

      aplicar('etapa' => 'qualificacao', 'etapa_motivo' => 'x')

      expect(lead.reload.lead_stage.label).to eq('fase-negociacao')
      expect(FunilAcao.count).to eq(0)
    end

    it 'ultima_chance com o lead em Novo não faz nada' do
      aplicar('etapa' => 'ultima_chance', 'etapa_motivo' => 'x')

      expect(lead.reload.lead_stage.label).to eq('fase-novo')
    end

    it 'ultima_chance leva Negociação a Última chance' do
      lead.update!(lead_stage: account.lead_stages.find_by(label: 'fase-negociacao'))

      aplicar('etapa' => 'ultima_chance', 'etapa_motivo' => 'esfriou')

      expect(lead.reload.lead_stage.label).to eq('fase-ultima-chance')
    end

    it 'não move se a ação foi desfeita há pouco' do
      allow(Ramon::FunilAutomatico).to receive(:desfeita_recente?).with(lead, acao: 'mover_etapa', alvo: 'Qualificação').and_return(true)

      aplicar('etapa' => 'qualificacao', 'etapa_motivo' => 'x')

      expect(lead.reload.lead_stage.label).to eq('fase-novo')
    end
  end

  describe 'depois de desfazer' do
    before { ligar('etapa_ia') }

    it 'a mesma decisão sem mensagem nova não move de novo; com mensagem nova, move' do
      aplicar('etapa' => 'qualificacao', 'etapa_motivo' => 'x')
      FunilAcao.last.desfazer!(create(:user, account: account))
      expect(lead.reload.lead_stage.label).to eq('fase-novo')

      aplicar('etapa' => 'qualificacao', 'etapa_motivo' => 'x')
      expect(lead.reload.lead_stage.label).to eq('fase-novo')

      create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming)
      aplicar('etapa' => 'qualificacao', 'etapa_motivo' => 'x')
      expect(lead.reload.lead_stage.label).to eq('fase-qualificacao')
    end

    it 'Perdido desfeito não volta na pausa seguinte, nem com outro motivo; com mensagem nova do cliente, volta' do
      ligar('perdido_recusa')
      aplicar('perdido' => { 'motivo' => 'Honorário', 'frase' => 'não tenho como pagar' })
      FunilAcao.last.desfazer!(create(:user, account: account))
      expect(lead.reload.lead_stage).not_to be_is_lost

      aplicar('perdido' => { 'motivo' => 'Já tem advogado', 'frase' => 'não quero' })
      expect(lead.reload.lead_stage).not_to be_is_lost
      expect(FunilAcao.where(acao: 'perdido').count).to eq(1)

      create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming)
      aplicar('perdido' => { 'motivo' => 'Honorário', 'frase' => 'não quero mesmo' })
      expect(lead.reload.lead_stage).to be_is_lost
    end
  end

  describe 'perdido' do
    before { ligar('perdido_recusa') }

    it 'com motivo do catálogo vira Perdido, etiqueta a conversa e cala a IA' do
      aplicar('perdido' => { 'motivo' => 'Honorário', 'frase' => 'não tenho como pagar' })

      lead.reload
      expect(lead.lead_stage).to be_is_lost
      expect(lead.lost_reason).to eq('Honorário')
      expect(conversa.reload.label_list).to include('desqualificado-ia')
      expect(Ramon::CopilotoModo.of(conversa)).to eq('manual')
      expect(FunilAcao.last).to have_attributes(peca: 'perdido_recusa', acao: 'perdido', alvo: 'Honorário')
      expect(FunilAcao.last.desfazer).to include('etapa_id' => account.lead_stages.find_by(label: 'fase-novo').id, 'modo' => 'rascunho',
                                                 'etapa_produzida_id' => lead.lead_stage_id)
    end

    it 'perdido que não é Hash com motivo ou frase é ignorado' do
      ['não', 'null', {}, { 'motivo' => '', 'frase' => '' }].each { |valor| aplicar('perdido' => valor) }

      expect(lead.reload.lead_stage).not_to be_is_lost
      expect(FunilAcao.count).to eq(0)
    end

    it 'frase vazia vira "recusa clara"' do
      aplicar('perdido' => { 'motivo' => 'Honorário', 'frase' => '' })

      expect(FunilAcao.last.motivo).to eq('recusa clara')
    end

    it 'motivo inventado vira Perdido com motivo de Automação' do
      aplicar('perdido' => { 'motivo' => 'Inventado', 'frase' => 'não quero' })

      expect(lead.reload.lead_stage).to be_is_lost
      expect(lead.lost_reason).to start_with('Automação:')
    end

    it 'em ensaio só registra' do
      ligar('perdido_recusa', 'ensaio')

      aplicar('perdido' => { 'motivo' => 'Honorário', 'frase' => 'não' })

      expect(lead.reload.lead_stage).not_to be_is_lost
      expect(FunilAcao.last).to be_ensaio
    end
  end

  it 'lead ganho não recebe nada' do
    ligar('etapa_ia')
    ligar('perdido_recusa')
    lead.update!(lead_stage: account.lead_stages.find_by(is_won: true))

    aplicar('etapa' => 'qualificacao', 'etapa_motivo' => 'x', 'perdido' => { 'motivo' => 'Honorário', 'frase' => 'não' })

    expect(lead.reload.lead_stage).to be_is_won
    expect(FunilAcao.count).to eq(0)
  end

  describe 'reunião' do
    let(:inicio) { 3.days.from_now.in_time_zone('America/Sao_Paulo').change(hour: 14, min: 0) }
    let(:decisao) { { 'reuniao' => { 'inicio' => inicio.strftime('%Y-%m-%dT%H:%M'), 'frase' => 'quinta às 14h está ótimo' } } }

    before { ligar('reuniao_ia') }

    it 'data futura vira tarefa de reunião, etapa Reunião agendada e desfazer com a tarefa' do
      aplicar(decisao)

      tarefa = lead.lead_tasks.find_by!(kind: 'meeting')
      expect(tarefa.due_at).to eq(inicio)
      expect(lead.reload.lead_stage.label).to eq('fase-reuniao-agendada')
      expect(FunilAcao.last).to have_attributes(peca: 'reuniao_ia', acao: 'marcar_reuniao', motivo: 'quinta às 14h está ótimo')
      expect(FunilAcao.last.desfazer).to eq('task_id' => tarefa.id)
    end

    it 'data no passado não faz nada' do
      aplicar('reuniao' => { 'inicio' => 2.days.ago.strftime('%Y-%m-%dT%H:%M'), 'frase' => 'x' })

      expect(lead.lead_tasks.where(kind: 'meeting')).to be_none
      expect(FunilAcao.count).to eq(0)
    end

    it 'início inválido ou reuniao que não é Hash não faz nada' do
      ['amanhã de manhã', 'não', {}, { 'inicio' => 'quando der', 'frase' => 'x' }].each { |valor| aplicar('reuniao' => valor) }

      expect(lead.lead_tasks.where(kind: 'meeting')).to be_none
      expect(FunilAcao.count).to eq(0)
    end

    it 'já existindo reunião aberta não faz nada' do
      create(:lead_task, account: account, lead: lead, kind: 'meeting', due_at: 5.days.from_now)

      aplicar(decisao)

      expect(lead.lead_tasks.where(kind: 'meeting').count).to eq(1)
      expect(FunilAcao.count).to eq(0)
    end

    it 'em ensaio só registra' do
      ligar('reuniao_ia', 'ensaio')

      aplicar(decisao)

      expect(lead.lead_tasks.where(kind: 'meeting')).to be_none
      expect(FunilAcao.last).to be_ensaio
    end

    it 'desfeita há pouco não marca de novo' do
      aplicar(decisao)
      FunilAcao.last.desfazer!(create(:user, account: account))
      expect(lead.lead_tasks.where(kind: 'meeting')).to be_none

      aplicar(decisao)

      expect(lead.lead_tasks.where(kind: 'meeting')).to be_none
    end
  end

  describe 'temperatura' do
    let(:decisao) { { 'temperatura' => 'quente', 'temperatura_motivo' => 'quer fechar' } }

    it 'grava só com a peça on, sem FunilAcao' do
      ligar('temperatura')

      aplicar(decisao)

      expect(lead.reload.custom_attributes['temperatura']).to include('nivel' => 'quente', 'motivo' => 'quer fechar')
      expect(FunilAcao.count).to eq(0)
    end

    it 'não grava em ensaio nem off' do
      aplicar(decisao)
      ligar('temperatura', 'ensaio')
      aplicar(decisao)

      expect(lead.reload.custom_attributes['temperatura']).to be_nil
    end

    it 'ignora nível inválido' do
      ligar('temperatura')

      aplicar('temperatura' => 'fervendo')

      expect(lead.reload.custom_attributes['temperatura']).to be_nil
    end
  end
end
