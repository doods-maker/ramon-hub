# Chegada de cliente na recepção (Equipe · Fatia 1): a Recepção avisa quem vai
# atender; o alerta insiste na tela da pessoa até ela responder em texto livre
# e, sem resposta em 3 min, volta pra quem avisou (Ramon::ChegadaEscalarJob).
class Chegada < ApplicationRecord
  self.table_name = 'ramon_chegadas'

  RECEPCAO = 'recepção'.freeze # mesmo time da Portaria (RamonPortariaListener::FALLBACK)
  ESCALAR_APOS = 3.minutes
  ZONA = 'America/Sao_Paulo'.freeze

  belongs_to :account
  belongs_to :criado_por, class_name: 'User'
  belongs_to :destinatario, class_name: 'User'

  validates :cliente_nome, presence: true

  scope :de_hoje, -> { where(created_at: Time.find_zone!(ZONA).now.all_day) }

  after_create_commit { transmitir('ramon.chegada.created') }
  after_update_commit { transmitir('ramon.chegada.updated') }

  def self.recepcao?(account, user)
    account.teams.find_by(name: RECEPCAO)&.members&.exists?(user.id) || false
  end

  def estado
    return 'respondido' if respondido_em.present?

    escalado_em.present? ? 'escalado' : 'aguardando'
  end

  def push_event_data
    {
      id: id, account_id: account_id, cliente_nome: cliente_nome, motivo: motivo, resposta: resposta, estado: estado,
      criado_por: { id: criado_por_id, name: criado_por&.name },
      destinatario: { id: destinatario_id, name: destinatario&.name },
      created_at: created_at.iso8601, respondido_em: respondido_em&.iso8601, escalado_em: escalado_em&.iso8601
    }
  end

  # FluxoExecucao#alvo_nome

  def nome_de_alvo = "Chegada: #{cliente_nome}"

  # Sem resposta e ainda não escalada (Ramon::ChegadaEscalarJob e a rotina do fluxo "Chegada de cliente", B5).
  def escalavel? = respondido_em.blank? && escalado_em.blank?

  # O update transmite ramon.chegada.updated (after_update_commit): o alerta volta a tocar na tela de quem avisou.
  def escalar! = escalavel? && update!(escalado_em: Time.current)

  private

  def transmitir(evento)
    ActionCableBroadcastJob.perform_later([criado_por.pubsub_token, destinatario.pubsub_token].uniq, evento, push_event_data)
  end
end
