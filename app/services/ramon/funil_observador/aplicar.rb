# Aplica a decisão (Hash) do observador do funil: cada efeito passa pela chave da peça em Ramon::FunilAutomatico.
# Um método privado por efeito, para as próximas peças (reunião, promessas, pendências) entrarem na sequência de perform.
class Ramon::FunilObservador::Aplicar
  # etapa decidida → [label destino, labels de origem permitidos]
  ETAPAS = { 'qualificacao' => ['fase-qualificacao', %w[fase-novo]],
             'ultima_chance' => ['fase-ultima-chance', %w[fase-reuniao-realizada fase-negociacao]] }.freeze
  TEMPERATURAS = %w[quente morno frio].freeze

  def initialize(lead, decisao)
    @lead = lead
    @decisao = decisao || {}
  end

  def perform
    @lead.reload
    return if @lead.won_at || @lead.lost_at

    mover_etapa
    perder_por_recusa
    return if @lead.lost_at # perdido agora: reunião, cobranças e pendências seriam trabalho para um lead encerrado

    marcar_reuniao
    gravar_temperatura
    promessas
    promessas_cumpridas
    pendencias
  end

  private

  def account = @lead.account

  def mover_etapa
    destino, origens = ETAPAS[@decisao['etapa']]
    return if destino.nil? || origens.exclude?(@lead.lead_stage&.label)

    etapa = account.lead_stages.find_by(label: destino)
    return if etapa.nil? || Ramon::FunilAutomatico.desfeita_recente?(@lead, acao: 'mover_etapa', alvo: etapa.name)

    Ramon::FunilRegras.mover_para_frente(@lead, destino, peca: 'etapa_ia', motivo: @decisao['etapa_motivo'])
  end

  # Desfeito há pouco = não refaz, com qualquer motivo: o motivo escolhido pelo LLM varia de uma pausa para outra.
  def perder_por_recusa
    recusa = recusa_valida
    perdido = account.lead_stages.find_by(is_lost: true)
    return if recusa.nil? || perdido.nil? || Ramon::FunilAutomatico.desfeita_recente?(@lead, acao: 'perdido')

    @lead.with_lock { perder(recusa, perdido) unless @lead.lead_stage.is_won || @lead.lead_stage.is_lost }
  end

  # Só Hash com motivo ou frase conta (o LLM às vezes devolve "não"/"null" em texto).
  def recusa_valida
    recusa = @decisao['perdido']
    recusa if recusa.is_a?(Hash) && (recusa['motivo'].present? || recusa['frase'].present?)
  end

  def perder(recusa, perdido)
    motivo = recusa['motivo'].presence_in(account.lost_reasons.pluck(:name))
    Ramon::FunilAutomatico.executar(@lead, peca: 'perdido_recusa', acao: 'perdido', motivo: recusa['frase'].presence || 'recusa clara',
                                           alvo: motivo || 'recusa', desfazer: desfazer_perdido(perdido)) do
      Ramon::Roteiro::Efeitos.perder(@lead, motivo)
    end
  end

  def desfazer_perdido(perdido)
    desfazer = { 'etapa_id' => @lead.lead_stage_id, 'etapa_produzida_id' => perdido.id }
    desfazer['modo'] = Ramon::CopilotoModo.of(@lead.conversation) if @lead.conversation
    desfazer
  end

  # Reunião combinada na conversa (dia e hora exatos): mesmo caminho do painel (etapa, Closer, lembretes, sino).
  # O desfazer é preenchido dentro do bloco (a tarefa só existe depois da chamada); em ensaio o bloco não roda.
  def marcar_reuniao
    inicio = reuniao_inicio
    return if inicio.nil? || @lead.lead_tasks.open_tasks.exists?(kind: 'meeting') ||
              Ramon::FunilAutomatico.desfeita_recente?(@lead, acao: 'marcar_reuniao', alvo: inicio.iso8601)
    return reuniao_ocupada(inicio) unless Ramon::FunilAutomatico.modo(account, 'reuniao_ia') == 'off' || livre?(inicio)

    desfazer = {}
    Ramon::FunilAutomatico.executar(@lead, peca: 'reuniao_ia', acao: 'marcar_reuniao', alvo: inicio.iso8601, desfazer: desfazer,
                                           motivo: @decisao['reuniao']['frase'].presence || 'reunião combinada na conversa') do
      agendar_reuniao(inicio, desfazer)
    end
  end

  # Conferência fora da transação do executar (faz HTTP ao Google). Só liga/ensaio importam: desligada, nada acontece.
  def livre?(inicio) = Ramon::ReuniaoAgendamento.livre?(@lead, inicio)

  # Horário pego: não marca e deixa o rastro no histórico do lead (sem FunilAcao; uma vez por horário). Em ensaio não grava.
  def reuniao_ocupada(inicio)
    return unless Ramon::FunilAutomatico.modo(account, 'reuniao_ia') == 'on'

    texto = "Reunião pedida para #{Ramon::ReuniaoAgendamento.quando(inicio)} não marcada: horário ocupado na agenda"
    return if @lead.lead_activities.exists?(kind: 'funil_auto', to_value: texto)

    LeadActivity.create!(account: account, lead: @lead, user: nil, kind: 'funil_auto', to_value: texto)
  end

  # false = a marcação não aconteceu (ex.: o fluxo falhou): sem registro nem atividade de IA.
  def agendar_reuniao(inicio, desfazer)
    antes = @lead.lead_stage_id
    Ramon::ReuniaoAgendamento.call(lead: @lead, starts_at: inicio, title: 'Reunião', user: nil)
    tarefa = @lead.lead_tasks.open_tasks.where(kind: 'meeting').order(:id).last
    return false if tarefa.nil?

    desfazer['task_id'] = tarefa.id
    # só se a marcação moveu a etapa; desfazer devolve a etapa e cancela a reunião
    desfazer.merge!('etapa_id' => antes, 'etapa_produzida_id' => @lead.lead_stage_id) if @lead.lead_stage_id != antes
  end

  # Só Hash com início válido e no futuro (o LLM às vezes devolve texto solto).
  def reuniao_inicio
    reuniao = @decisao['reuniao']
    return unless reuniao.is_a?(Hash) && reuniao['inicio'].present?

    inicio = Time.find_zone!('America/Sao_Paulo').parse(reuniao['inicio'].to_s)
    inicio if inicio&.future?
  rescue ArgumentError
    nil
  end

  # Sem FunilAcao (ruído no resumo); só com a peça on — em ensaio não grava.
  def gravar_temperatura
    nivel = @decisao['temperatura']
    return unless TEMPERATURAS.include?(nivel) && Ramon::FunilAutomatico.modo(account, 'temperatura') == 'on'

    @lead.update!(custom_attributes: (@lead.custom_attributes || {}).merge(
      'temperatura' => { 'nivel' => nivel, 'motivo' => @decisao['temperatura_motivo'].to_s.truncate(250), 'em' => Time.current.iso8601 }
    ))
  end

  # Promessa do cliente vira follow-up do SDR ("Cobrar: …") no dia prometido, 10h de São Paulo.
  # Prazo inválido ou que já passou = item ignorado (cobrar no passado é ruído); o mesmo título aberto não duplica.
  def promessas
    itens(@decisao['promessas']).each do |item|
      titulo = "Cobrar: #{item['o_que']}".truncate(255)
      prazo = prazo_promessa(item['prazo'])
      next if item['o_que'].blank? || prazo.nil? || @lead.lead_tasks.open_tasks.exists?(title: titulo) || ja_registrada?(titulo)

      criar_cobranca(titulo, prazo, item)
    end
  end

  # A promessa continua na conversa a cada pausa: a FunilAcao (ensaio ou real, desfeita ou não) é a memória — tarefa
  # apagada, concluída ou desfeita por gente não renasce.
  def ja_registrada?(titulo)
    registros = FunilAcao.where(lead: @lead, acao: 'promessa', alvo: titulo)
    # ligada de verdade, o que só foi visto em ensaio ainda não virou tarefa
    registros = registros.reais if Ramon::FunilAutomatico.modo(account, 'promessas') == 'on'
    registros.exists?(['created_at > ?', 30.days.ago]) ||
      Ramon::FunilAutomatico.desfeita_recente?(@lead, acao: 'promessa', alvo: titulo)
  end

  def criar_cobranca(titulo, prazo, item)
    desfazer = {}
    Ramon::FunilAutomatico.executar(@lead, peca: 'promessas', acao: 'promessa', alvo: titulo, desfazer: desfazer,
                                           motivo: "cliente prometeu: #{item['o_que']}") do
      tarefa = @lead.lead_tasks.create!(account: account, user: @lead.sdr || @lead.closer, kind: 'follow_up',
                                        title: titulo, due_at: prazo)
      desfazer['task_id'] = tarefa.id
    end
  end

  # 'AAAA-MM-DD' → esse dia às 10h (SP). Hoje já depois das 10h = daqui a 1h ("mando hoje" não se perde); dia passado = nil.
  def prazo_promessa(prazo)
    return unless prazo.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    data = Time.find_zone!('America/Sao_Paulo').parse("#{prazo} 10:00")
    return if data.nil?

    data.future? ? data : (1.hour.from_now if data.to_date == Time.current.in_time_zone('America/Sao_Paulo').to_date)
  rescue ArgumentError
    nil
  end

  # Só conclui "Cobrar:" aberta DESTE lead (o id vem do LLM); ids soltos/alheios são ignorados.
  def promessas_cumpridas
    ids = Array(@decisao['promessas_cumpridas']).filter_map { |id| Integer(id, exception: false) }.uniq
    return if ids.empty?

    # em ensaio, o "faria" já registrado não se repete; ligada, o que só foi visto em ensaio ainda precisa ser concluído
    ensaio = Ramon::FunilAutomatico.modo(account, 'promessas') == 'ensaio'
    @lead.lead_tasks.open_tasks.where(id: ids).where('title LIKE ?', 'Cobrar:%').find_each do |task|
      next if FunilAcao.exists?(lead: @lead, acao: 'promessa_cumprida', alvo: task.id.to_s, ensaio: ensaio)

      Ramon::FunilAutomatico.executar(@lead, peca: 'promessas', acao: 'promessa_cumprida', alvo: task.id.to_s,
                                             motivo: "cumprida: #{task.title}") { task.complete!(nil) }
    end
  end

  # Documentos que o cliente ainda deve (chip no card). Sem FunilAcao; só com a peça on — em ensaio não grava.
  # A lista substitui a anterior a cada pausa; vazia remove a chave.
  def pendencias
    return unless @decisao.key?('pendencias') && Ramon::FunilAutomatico.modo(account, 'pendencias') == 'on'

    lista = lista_pendencias
    return if lista == Array(@lead.custom_attributes&.dig('pendencias_docs'))

    atributos = (@lead.custom_attributes || {}).except('pendencias_docs')
    atributos['pendencias_docs'] = lista if lista.any?
    @lead.update!(custom_attributes: atributos)
  end

  def lista_pendencias
    Array.wrap(@decisao['pendencias']).grep(String).map { |i| i.strip.truncate(40) }.compact_blank.first(5)
  end

  # Só Array de Hashes conta; item malformado é pulado.
  def itens(valor) = Array.wrap(valor).grep(Hash)
end
