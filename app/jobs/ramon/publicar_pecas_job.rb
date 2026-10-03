# Cron (1 min): publica no Instagram as peças agendadas que venceram. Sem retry
# automático — falha vira `falhou` + push, e o Eduardo decide tentar de novo.
class Ramon::PublicarPecasJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    marcar_interrompidas
    Peca.where(status: 'agendado').where(agendado_para: ..Time.current).find_each { |peca| publicar(peca) }
  end

  private

  def publicar(peca)
    peca.transicionar!(de: 'agendado', para: 'publicando', publicacao_iniciada_em: Time.current)
    # ig_media_id gravado = já está no ar; nunca mandar de novo pra Meta.
    return peca.update!(status: 'publicado') if peca.ig_media_id.present?

    publisher = Ramon::InstagramPublisher.new(peca)
    peca.update!(ig_media_id: publisher.publicar) # grava no instante do publish
    peca.update!(status: 'publicado', permalink: publisher.permalink(peca.ig_media_id), erro: nil)
    Ramon::ConteudoDriveJob.perform_later(peca.id)
    avisar("Publicado no Instagram: #{peca.gancho}", peca.permalink || 'link indisponível — ver no app')
  rescue Peca::TransicaoInvalida
    nil # outro processo já pegou esta peça
  rescue StandardError => e
    peca.update!(status: 'falhou', erro: e.message)
    avisar("Publicação falhou: #{peca.gancho}", e.message)
  end

  def marcar_interrompidas
    Peca.where(status: 'publicando').where(publicacao_iniciada_em: ...Peca::TRAVA.ago).find_each do |peca|
      peca.update!(status: 'falhou', erro: 'Publicação interrompida no meio — conferir no Instagram antes de tentar de novo.')
    end
  end

  def avisar(titulo, corpo)
    Ramon::NtfyPushJob.perform_later(nil, title: titulo, body: corpo)
  end
end
