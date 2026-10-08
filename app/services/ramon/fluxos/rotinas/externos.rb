# B5-externos: rotinas prontas das automações que começam FORA do funil — o MESMO código de hoje.
# Contrato do registro Ramon::Fluxos::Rotinas: ROTINAS nome → alvo + rodar(nome, ctx) → String (o resumo da trilha); o
# ensaio só descreve; alvo errado = PassoImpossivel (falha na hora, sem nova tentativa). Na carga este módulo não cita
# Ramon::Fluxos::Migracao (autoload circular).
# Os pesados pedem o mesmo job de hoje (perform_later), com a fila, as travas e as novas tentativas do código (ata 3×,
# ZapSign 5×, documento do Painel 5×, Drive 3×): o Ramon::FluxoRelogioJob devolve à fila a execução 'rodando' há mais
# de 10 min — o whisper de uma reunião longa dentro do passo seria transcrito de novo.
module Ramon::Fluxos::Rotinas::Externos
  # As 6 migrações (juntadas em Migracao::GRUPOS pelo registro); quem decide cada evento é Ramon::Fluxos::Externos.evento.
  GRUPOS = {
    'assinatura_painel' => { env: 'RAMON_FLUXO_ASSINATURA_PAINEL', faz: 'a conferência das assinaturas do Painel do Cliente',
                             fluxos: { 'assinatura_painel' => 'assinatura_painel' }.freeze },
    'contrato_zapsign' => { env: 'RAMON_FLUXO_CONTRATO_ZAPSIGN', faz: 'o histórico e o sino do contrato no ZapSign',
                            fluxos: { 'contrato_zapsign_assinado' => 'contrato_assinado',
                                      'contrato_zapsign_recusado' => 'contrato_recusado' }.freeze },
    'documento_painel' => { env: 'RAMON_FLUXO_DOCUMENTO_PAINEL', faz: 'os documentos enviados pelo Painel (Drive, push e ADVBOX)',
                            fluxos: { 'documento_painel' => 'documento_painel' }.freeze },
    'chegada_cliente' => { env: 'RAMON_FLUXO_CHEGADA', faz: 'a escalada da chegada de cliente',
                           fluxos: { 'chegada_cliente' => 'chegada_cliente' }.freeze },
    'ata_reuniao' => { env: 'RAMON_FLUXO_ATA_REUNIAO', faz: 'a ata das reuniões gravadas',
                       fluxos: { 'ata_reuniao' => 'reuniao_gravada' }.freeze },
    'acervo_pecas' => { env: 'RAMON_FLUXO_ACERVO_PECAS', faz: 'o acervo das peças (Drive e Notion)',
                        fluxos: { 'acervo_pecas_drive' => 'peca_publicada', 'acervo_pecas_notion' => 'peca_mudou_status' }.freeze }
  }.freeze
  # 'outro' = o alvo é o registro do evento (assinatura/documento do Painel, chegada, reunião gravada, peça); o contrato é do lead.
  ROTINAS = {
    'conferir_assinatura_painel' => 'outro', 'aviso_contrato' => 'lead', 'processar_envio_painel' => 'outro',
    'escalar_chegada' => 'outro', 'escrever_ata' => 'outro', 'acervo_drive' => 'outro', 'espelho_notion' => 'outro'
  }.freeze
  ALVOS = { 'PortalAssinatura' => 'uma assinatura do Painel do Cliente', 'PortalEnvio' => 'um documento enviado pelo Painel',
            'Chegada' => 'uma chegada de cliente', 'Reuniao' => 'uma reunião gravada', 'Peca' => 'uma peça do Instagram' }.freeze

  module_function

  def rodar(nome, ctx) = public_send(nome, ctx)

  def conferir_assinatura_painel(ctx)
    assinatura = alvo!(ctx, PortalAssinatura)
    return "faria: conferir no ZapSign a assinatura \"#{assinatura.nome}\" e marcar no Painel" if ctx.ensaio?

    Ramon::ZapsignStatusJob.perform_later(assinatura.id)
    "conferência no ZapSign pedida (\"#{assinatura.nome}\")"
  end

  # O selo (custom_attributes.zapsign.status) é gravado pelo código antes do evento; aqui só o histórico e o sino de hoje.
  def aviso_contrato(ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    status = lead.custom_attributes&.dig('zapsign', 'status').to_s
    rotulo = Ramon::ZapsignLeadStatusJob::STATUS.dig(status, 2)
    return "contrato: o ZapSign não diz assinado nem recusado (#{status.presence || 'sem status'})" if rotulo.nil?
    return "faria: histórico e sino a todos — contrato #{rotulo}" if ctx.ensaio?

    Ramon::ZapsignLeadStatusJob.avisar(lead, status)
    "histórico e sino a todos — contrato #{rotulo}"
  end

  def processar_envio_painel(ctx)
    envio = alvo!(ctx, PortalEnvio)
    return "faria: guardar \"#{envio.item}\" no Drive, push no celular e as 2 tarefas no ADVBOX" if ctx.ensaio?

    Ramon::PortalEnvioJob.perform_later(envio.id)
    "documento \"#{envio.item}\": Drive, push e tarefas do ADVBOX pedidos"
  end

  def escalar_chegada(ctx)
    chegada = alvo!(ctx, Chegada)
    return 'chegada já respondida (ou já escalada): não escala' unless chegada.escalavel?
    return 'faria: escalar — o alerta volta a tocar na tela de quem avisou' if ctx.ensaio?

    chegada.escalar!
    'escalou: o alerta voltou a tocar na tela de quem avisou'
  end

  def escrever_ata(ctx)
    reuniao = alvo!(ctx, Reuniao)
    return "faria: transcrever o áudio e escrever a ata de \"#{reuniao.titulo_exibicao}\"" if ctx.ensaio?

    Ramon::ReuniaoAtaJob.perform_later(reuniao.id)
    'ata pedida (transcrição e IA na fila de sempre; a ata aparece na reunião)'
  end

  def acervo_drive(ctx)
    peca = alvo!(ctx, Peca)
    return "faria: copiar a peça \"#{peca.gancho}\" (imagens e legenda) para o Drive" if ctx.ensaio?

    Ramon::ConteudoDriveJob.perform_later(peca.id)
    "cópia no Drive pedida (\"#{peca.gancho}\")"
  end

  def espelho_notion(ctx)
    peca = alvo!(ctx, Peca)
    return "faria: espelhar o status \"#{peca.status}\" no Notion" if ctx.ensaio?

    Ramon::NotionEspelhoJob.perform_later(peca.id)
    "espelho do status \"#{peca.status}\" no Notion pedido"
  end

  def alvo!(ctx, classe)
    alvo = ctx.execucao.alvo
    return alvo if alvo.is_a?(classe)

    raise Ramon::Fluxos::PassoImpossivel, "esta rotina só roda com #{ALVOS.fetch(classe.name)} (o Testar com um lead não serve aqui)"
  end
end
