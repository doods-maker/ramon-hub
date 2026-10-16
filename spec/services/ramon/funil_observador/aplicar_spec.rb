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
      expect(FunilAcao.last.desfazer).to eq('task_id' => tarefa.id, 'etapa_id' => account.lead_stages.find_by(label: 'fase-novo').id,
                                            'etapa_produzida_id' => lead.lead_stage_id)
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

    it 'desfazer devolve a etapa e cancela a reunião' do
      aplicar(decisao)

      expect(FunilAcao.last.desfazer!(create(:user, account: account))).to be(true)

      expect(lead.reload.lead_stage.label).to eq('fase-novo')
      expect(lead.lead_tasks.where(kind: 'meeting')).to be_none
    end

    it 'sem tarefa criada pela marcação não registra FunilAcao nem atividade' do
      allow(Ramon::ReuniaoAgendamento).to receive(:call)

      aplicar(decisao)

      expect(FunilAcao.count).to eq(0)
      expect(lead.lead_activities.where(kind: 'funil_auto')).to be_none
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

  describe 'promessas' do
    let(:sdr) { create(:user, account: account) }
    let(:decisao) { { 'promessas' => [{ 'o_que' => 'mandar o laudo', 'prazo' => '2026-10-20', 'documento' => true }] } }

    before do
      travel_to Time.zone.parse('2026-10-16 12:00')
      lead.update!(sdr: sdr)
      ligar('promessas')
    end

    it 'vira follow-up do SDR no dia prometido às 10h de São Paulo, com desfazer' do
      aplicar(decisao)

      tarefa = lead.lead_tasks.last
      expect(tarefa).to have_attributes(kind: 'follow_up', title: 'Cobrar: mandar o laudo', user_id: sdr.id)
      expect(tarefa.due_at).to eq(Time.zone.parse('2026-10-20 10:00 -03:00'))
      expect(FunilAcao.last).to have_attributes(acao: 'promessa', desfazer: { 'task_id' => tarefa.id })
    end

    it 'a mesma promessa duas vezes gera uma tarefa só' do
      2.times { aplicar(decisao) }

      expect(lead.lead_tasks.where(title: 'Cobrar: mandar o laudo').count).to eq(1)
    end

    it 'prazo inválido ou no passado e item malformado são ignorados' do
      aplicar('promessas' => [{ 'o_que' => 'a', 'prazo' => '2026-10-10' }, { 'o_que' => 'b', 'prazo' => 'amanhã' },
                              'texto solto', { 'prazo' => '2026-10-20' }, nil])

      expect(lead.lead_tasks.count).to eq(0)
    end

    it 'em ensaio, duas pausas registram uma FunilAcao só' do
      ligar('promessas', 'ensaio')

      2.times { aplicar(decisao) }

      expect(FunilAcao.where(acao: 'promessa').count).to eq(1)
      expect(lead.lead_tasks.count).to eq(0)
    end

    it 'tarefa concluída por gente não é recriada na pausa seguinte' do
      aplicar(decisao)
      lead.lead_tasks.last.complete!(nil)

      aplicar(decisao)

      expect(lead.lead_tasks.count).to eq(1)
    end

    it 'promessa desfeita não volta sem mensagem nova do cliente' do
      aplicar(decisao)
      FunilAcao.last.desfazer!(create(:user, account: account))

      aplicar(decisao)

      expect(lead.lead_tasks.count).to eq(0)
    end

    it 'prazo hoje já depois das 10h vira daqui a 1 hora' do
      travel_back # o before já congelou o relógio; travel_to aninhado com bloco é proibido
      agora = Time.find_zone!('America/Sao_Paulo').parse('2026-10-16 14:00')
      travel_to(agora) { aplicar('promessas' => [{ 'o_que' => 'mandar hoje', 'prazo' => '2026-10-16' }]) }

      expect(lead.lead_tasks.last.due_at).to eq(agora + 1.hour)
    end

    it 'visto em ensaio e depois ligado: vira tarefa uma vez' do
      ligar('promessas', 'ensaio')
      aplicar(decisao)
      ligar('promessas')

      2.times { aplicar(decisao) }

      expect(lead.lead_tasks.count).to eq(1)
    end

    it 'promessas que não é lista é ignorada' do
      aplicar('promessas' => 'nenhuma')

      expect(lead.lead_tasks.count).to eq(0)
    end
  end

  describe 'promessas_cumpridas' do
    before { ligar('promessas') }

    it 'conclui a tarefa Cobrar: aberta do lead' do
      tarefa = create(:lead_task, account: account, lead: lead, title: 'Cobrar: laudo')

      aplicar('promessas_cumpridas' => [tarefa.id])

      expect(tarefa.reload.completed_at).to be_present
      expect(FunilAcao.last).to have_attributes(acao: 'promessa_cumprida', alvo: tarefa.id.to_s)
    end

    it 'ignora tarefa de outro lead, que não é Cobrar: ou ids inválidos' do
      alheia = create(:lead_task, account: account, title: 'Cobrar: laudo')
      outra = create(:lead_task, account: account, lead: lead, title: 'Ligar')

      aplicar('promessas_cumpridas' => [alheia.id, outra.id, 'x', nil])

      expect([alheia, outra].map { |t| t.reload.completed_at }).to all(be_nil)
    end
  end

  describe 'promessas_cumpridas em ensaio' do
    it 'não repete o registro para a mesma tarefa' do
      ligar('promessas', 'ensaio')
      tarefa = create(:lead_task, account: account, lead: lead, title: 'Cobrar: laudo')

      2.times { aplicar('promessas_cumpridas' => [tarefa.id]) }

      expect(FunilAcao.where(acao: 'promessa_cumprida').count).to eq(1)
    end
  end

  describe 'pendencias' do
    it 'lista igual à gravada não atualiza o lead' do
      ligar('pendencias')
      lead.update!(custom_attributes: { 'pendencias_docs' => ['laudo'] })
      antes = lead.reload.updated_at

      travel_to(1.hour.from_now) { aplicar('pendencias' => ['laudo']) }

      expect(lead.reload.updated_at).to eq(antes)
    end

    it 'grava a lista (até 5, 40 caracteres) só com a peça on, sem FunilAcao' do
      ligar('pendencias')

      aplicar('pendencias' => ['laudo', 'x' * 60, 'a', 'b', 'c', 'd', 3, ''])

      lista = lead.reload.custom_attributes['pendencias_docs']
      expect(lista.size).to eq(5)
      expect(lista[1].length).to eq(40)
      expect(FunilAcao.count).to eq(0)
    end

    it 'lista vazia remove a chave' do
      ligar('pendencias')
      lead.update!(custom_attributes: { 'pendencias_docs' => ['laudo'], 'outra' => 1 })

      aplicar('pendencias' => [])

      expect(lead.reload.custom_attributes).to eq('outra' => 1)
    end

    it 'não grava em ensaio' do
      ligar('pendencias', 'ensaio')

      aplicar('pendencias' => ['laudo'])

      expect(lead.reload.custom_attributes['pendencias_docs']).to be_nil
    end
  end
end
