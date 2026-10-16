# Ação automática do funil (ver Ramon::FunilAutomatico). Ensaio = só registrada, nunca aplicada.
class FunilAcao < ApplicationRecord
  self.table_name = 'ramon_funil_acoes'

  belongs_to :account
  belongs_to :lead
  belongs_to :desfeita_por, class_name: 'User', optional: true

  scope :reais, -> { where(ensaio: false) }
  scope :vivas, -> { reais.where(desfeita_em: nil) }

  # Rótulo de cada ação (chip do card e resumo das 8h); %s = o alvo. Sem %s, o alvo não diz nada a quem lê (id, dias).
  ROTULOS = { 'mover_etapa' => 'moveu para %s', 'marcar_ganho' => 'marcou Ganho', 'perdido' => 'marcou Perdido (%s)',
              'marcar_reuniao' => 'marcou reunião para %s', 'promessa' => 'criou cobrança (%s)',
              'promessa_cumprida' => 'concluiu cobrança', 'avisar_no_show' => 'avisou no-show',
              'reativar' => 'rascunho de retomada' }.freeze

  # Texto curto do chip do card ("IA: …") e do resumo. Ação sem rótulo cai no nome técnico.
  def texto
    rotulo = ROTULOS[acao.to_s]
    return [acao.to_s.tr('_', ' '), alvo].compact_blank.join(' → ') if rotulo.nil?

    rotulo.include?('%s') ? format(rotulo, alvo_legivel) : rotulo
  end

  # Última ação viva do lead nas últimas 24h, para o chip do card (nil = sem chip).
  def self.chip(lead) = chips([lead.id])[lead.id]

  # Em lote (índice do Kanban): UMA query para todos os leads → { lead_id => { id:, texto: } }.
  # Só ação que se desfaz: um aviso (no-show, cobrança concluída) não tira do card o "Desfazer" de antes.
  def self.chips(lead_ids)
    ultimas = vivas.where(lead_id: lead_ids, created_at: 24.hours.ago..).where("desfazer <> '{}'::jsonb").order(:id).index_by(&:lead_id)
    ultimas.transform_values { |a| { id: a.id, texto: a.texto } }
  end

  # Reverte o que a ação fez (payload `desfazer`). false = já desfeita. O banco volta tudo ou nada sob o lock do lead;
  # cancelar a reunião (sino, Disparo, push) só depois do commit — um aviso não sai de um desfazer que deu rollback.
  def desfazer!(user)
    reuniao = nil
    feito = lead.with_lock do
      reload
      next false if desfeita_em || movida_depois?

      restaurar_etapa
      restaurar_modo
      reuniao = desfazer_tarefa
      update!(desfeita_em: Time.current, desfeita_por: user)
      true
    end
    Ramon::ReuniaoAgendamento.cancelar(task: reuniao, user: user) if feito && reuniao
    feito
  end

  # Um humano mexeu na etapa depois da IA: desfazer sobrescreveria a decisão dele (só vale p/ ações que mudam etapa).
  # etapa_produzida_id vem no payload; ações antigas, sem ele, caem na busca pelo nome/tipo.
  def movida_depois?
    produzida_id = desfazer['etapa_produzida_id'] || etapa_produzida&.id
    desfazer['etapa_id'].present? && produzida_id.present? && lead.lead_stage_id != produzida_id
  end

  private

  # Início de reunião é gravado em ISO 8601: quem lê vê "20/10 14:00" (horário de São Paulo).
  def alvo_legivel
    return alvo.to_s unless alvo.to_s.match?(/\A\d{4}-\d{2}-\d{2}T/)

    Time.zone.parse(alvo).in_time_zone('America/Sao_Paulo').strftime('%d/%m %H:%M')
  end

  def etapa_produzida
    case acao
    when 'mover_etapa', 'marcar_ganho' then account.lead_stages.find_by(name: alvo)
    when 'perdido' then account.lead_stages.find_by(is_lost: true)
    end
  end

  def restaurar_etapa
    return if desfazer['etapa_id'].blank?

    # lost_reason só existe no payload quando a etapa de volta é Perdido; senão o lead zera o motivo
    lead.update!(lead_stage_id: desfazer['etapa_id'], lost_reason: desfazer['lost_reason'])
    desfazer_limite
  end

  # O avanço pode ter encerrado um modo "sozinha até…" (Lead → CopilotoLimite.verificar). Carimbo desta ação (não
  # anterior a ela) e o lead, de volta, sem alcançar o limite: devolve o modo (o desfazer confere carimbo e rascunho).
  def desfazer_limite
    conversa = lead.conversation
    carimbo = conversa&.custom_attributes&.[]('copiloto_limite')
    return unless carimbo.is_a?(Hash) && Ramon::CopilotoLimite::NIVEIS.include?(carimbo['limite'])
    return if Time.zone.parse(carimbo['em'].to_s).to_i < created_at.to_i || Ramon::CopilotoLimite.atingido?(carimbo['limite'], lead)

    Ramon::CopilotoLimite.desfazer(conversa, carimbo['limite'])
  end

  # O inverso do calar (que guardou o modo de antes em CopilotoModo::MODO_ANTES). Sem o guardado (já restaurado por
  # outro caminho, ou ação antiga), vale o 'modo' gravado na ação.
  def restaurar_modo
    conversa = lead.conversation
    return if desfazer['modo'].blank? || conversa.nil?

    Ramon::CopilotoModo.restaurar(conversa) ||
      conversa.update!(custom_attributes: (conversa.custom_attributes || {}).merge('copiloto_modo' => desfazer['modo']))
    Ramon::Roteiro::Efeitos.tirar_etiqueta(conversa)
  end

  # Follow-up some aqui (dentro do lock); a reunião volta para ser cancelada depois do commit.
  def desfazer_tarefa
    task = lead.lead_tasks.find_by(id: desfazer['task_id'])
    return if task.nil?
    return task if task.kind == 'meeting'

    task.destroy!
    nil
  end
end
