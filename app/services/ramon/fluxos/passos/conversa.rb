# Passos que escrevem na conversa. Mensagem ao cliente SEMPRE como rascunho (nota privada
# com o prefixo do carimbo) — quem envia é uma pessoa.
module Ramon::Fluxos::Passos::Conversa
  module_function

  def rascunho_texto(config, ctx)
    texto = ctx.interpolar(config['texto'])
    return { saida: 's', resumo: "faria: rascunho \"#{texto.truncate(120)}\"" } if ctx.ensaio?

    escrever(ctx, "#{cabecalho(config)}\n#{texto}", onde: config['onde'])
    { saida: 's', resumo: "rascunho criado: #{texto.truncate(120)}" }
  end

  def nota_privada(config, ctx)
    texto = ctx.interpolar(config['texto'])
    return { saida: 's', resumo: "faria: nota \"#{texto.truncate(120)}\"" } if ctx.ensaio?

    escrever(ctx, texto)
    { saida: 's', resumo: "nota: #{texto.truncate(120)}" }
  end

  def acao_chatwoot(config, ctx)
    acoes = Array(config['acoes'])
    descricao = acoes.pluck('action_name').join(', ')
    return { saida: 's', resumo: "faria: #{descricao}" } if ctx.ensaio?
    raise Ramon::Fluxos::PassoImpossivel, 'ação do Chatwoot precisa de uma conversa' if ctx.conversa.blank?

    Ramon::Fluxos::AcaoChatwootService.new(ctx.execucao, ctx.conversa, acoes).perform
    { saida: 's', resumo: descricao }
  end

  # "RASCUNHO (revisar antes de enviar):"; com título (B4.1), "RASCUNHO (revisar antes de enviar) — confirmação de reunião:"
  def cabecalho(config)
    titulo = config['titulo'].to_s.strip
    titulo.empty? ? Ramon::RascunhoCarimbo::PREFIXO : "#{Ramon::RascunhoCarimbo::PREFIXO.delete_suffix(':')} — #{titulo}:"
  end

  # onde 'notas_do_lead' (B4.1): como o rascunho de confirmação do código, mesmo se o lead tiver conversa.
  def escrever(ctx, texto, onde: nil)
    if ctx.conversa && onde != 'notas_do_lead'
      Messages::MessageBuilder.new(nil, ctx.conversa, { content: texto, private: true,
                                                        content_attributes: { ramon_fluxo_execucao_id: ctx.execucao.id } }).perform
    elsif ctx.lead
      ctx.lead.lead_notes.create!(account: ctx.lead.account, body: texto.truncate(1000))
    else
      raise Ramon::Fluxos::PassoImpossivel, 'sem conversa nem lead para escrever'
    end
  end
end
