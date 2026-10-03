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
    return concluir_ja_no_ar(peca) if peca.ig_media_id.present?

    publisher = Ramon::InstagramPublisher.new(peca)
    peca.update!(ig_media_id: publisher.publicar) # grava no instante do publish
    peca.update!(status: 'publicado', permalink: publisher.permalink(peca.ig_media_id), erro: nil)
    pos_publicacao(peca)
  rescue Peca::TransicaoInvalida
    nil # outro processo já pegou esta peça
  rescue StandardError => e
    # id gravado = está no ar: nunca vira `falhou`.
    return no_ar_apos_erro(peca, e) if peca.ig_media_id.present?

    peca.update!(status: 'falhou', erro: e.message)
    avisar("Publicação falhou: #{peca.gancho}", e.message)
  end

  def concluir_ja_no_ar(peca)
    peca.update!(status: 'publicado', erro: nil)
    pos_publicacao(peca)
  end

  def pos_publicacao(peca)
    Ramon::ConteudoDriveJob.perform_later(peca.id)
    avisar("Publicado no Instagram: #{peca.gancho}", peca.permalink || 'link indisponível — ver no app')
  end

  # Algo falhou DEPOIS do id gravado (permalink, callback, fila): update_columns pula callbacks.
  def no_ar_apos_erro(peca, erro)
    Rails.logger.warn("PublicarPecasJob: peça #{peca.id} no ar (#{peca.ig_media_id}), pós-publicação falhou: #{erro.message}")
    peca.update_columns(status: 'publicado', erro: nil, ig_media_id: peca.ig_media_id)
    pos_publicacao(peca)
  rescue StandardError => e
    Rails.logger.warn("PublicarPecasJob: peça #{peca.id} no ar, aviso/acervo não saiu: #{e.message}")
  end

  def marcar_interrompidas
    Peca.where(status: 'publicando').where(publicacao_iniciada_em: ...Peca::TRAVA.ago).find_each { |peca| interromper(peca) }
  end

  def interromper(peca)
    if peca.ig_media_id.present?
      peca.transicionar!(de: 'publicando', para: 'publicado', erro: nil)
      pos_publicacao(peca)
    else
      peca.transicionar!(de: 'publicando', para: 'falhou',
                         erro: 'Publicação interrompida no meio — conferir no Instagram antes de tentar de novo.')
    end
  rescue Peca::TransicaoInvalida
    nil # outro processo já resolveu
  end

  def avisar(titulo, corpo)
    Ramon::NtfyPushJob.perform_later(nil, title: titulo, body: corpo)
  end
end
