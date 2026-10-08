# 3 min depois do aviso: se ninguém respondeu, marca a escalada — o update
# transmite ramon.chegada.updated e o alerta toca pra quem avisou.
class Ramon::ChegadaEscalarJob < ApplicationJob
  queue_as :default

  def perform(chegada_id)
    Chegada.find_by(id: chegada_id)&.escalar!
  end
end
