# 3 min depois do aviso: se ninguém respondeu, marca a escalada — o update
# transmite ramon.chegada.updated e o alerta toca pra quem avisou.
class Ramon::ChegadaEscalarJob < ApplicationJob
  queue_as :default

  def perform(chegada_id)
    chegada = Chegada.find_by(id: chegada_id)
    return if chegada.nil? || chegada.respondido_em.present? || chegada.escalado_em.present?

    chegada.update!(escalado_em: Time.current)
  end
end
