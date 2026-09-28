# 8h (BRT): avisa as novidades do espelho noturno. Cliente com e-mail recebe 1 e-mail
# detalhado (etapas "delicadas" nunca vão por e-mail); a equipe recebe 1 resumo com o
# texto pronto de WhatsApp e o link wa.me de cada cliente — quem manda é uma pessoa.
# Desligado até o Eduardo aprovar os textos: PORTAL_AVISOS=on liga (texto = gate dele).
class Ramon::PortalAvisosJob < ApplicationJob
  queue_as :scheduled_jobs

  EQUIPE_PADRAO = 'ramonantonio.comercial@gmail.com'.freeze # teste antes da Gabriela (decisão Eduardo 28/09)

  def perform
    return unless ENV['PORTAL_AVISOS'] == 'on'

    linhas = []
    PortalCliente.where.not(convidado_em: nil).find_each { |cliente| linhas.concat(avisar(cliente)) }
    return if linhas.empty?

    # ponytail: se o resumo falhar, as novidades já ficaram avisadas — o selo "Novo" segue no painel.
    Ramon::PortalMailer.with(linhas: linhas, para: ENV.fetch('PORTAL_AVISO_EQUIPE_EMAIL', EQUIPE_PADRAO)).resumo_equipe.deliver_now
  end

  private

  def avisar(cliente)
    pendentes = pendentes(cliente)
    return [] if pendentes.empty?

    por_email = enviar_email(cliente, pendentes)
    marcar_avisadas!(cliente)
    pendentes.map { |p, n| linha(cliente, p, n, por_email && por_email?(n)) }
  rescue StandardError => e
    Rails.logger.warn("[Ramon::PortalAvisosJob] cliente=#{cliente.id} #{e.class}: #{e.message}")
    []
  end

  def pendentes(cliente)
    cliente.processos.flat_map { |p| Array(p['novidades']).reject { |n| n['avisada'] }.map { |n| [p, n] } }
  end

  # Etapa/marco delicado nunca vai por e-mail automático.
  def enviar_email(cliente, pendentes)
    comuns = pendentes.select { |_p, n| por_email?(n) }
    return false if cliente.email.blank? || comuns.empty?

    Ramon::PortalMailer.with(cliente: cliente, itens: comuns.map { |p, n| item(p, n) }).novidade.deliver_now
    true
  end

  # 'email' => false = etapa sem e-mail no dicionário v2; nil (novidade antiga ou marco) conta como true.
  def por_email?(novidade) = !novidade['delicada'] && novidade['email'] != false

  def marcar_avisadas!(cliente)
    cliente.update!(processos: cliente.processos.map do |p|
      p.merge('novidades' => Array(p['novidades']).map { |n| n.merge('avisada' => true) })
    end)
  end

  def item(processo, novidade)
    { 'tipo' => tipo_amigavel(processo['tipo']), 'titulo' => novidade['titulo'], 'o_que_esperar' => novidade['o_que_esperar'] }
  end

  def linha(cliente, processo, novidade, recebeu_email)
    texto = texto_whatsapp(cliente, novidade)
    item(processo, novidade).merge(
      'nome' => cliente.nome, 'responsavel' => processo['responsavel'], 'delicada' => novidade['delicada'] == true,
      'email' => status_email(cliente, novidade, recebeu_email), 'texto_whatsapp' => texto, 'link_wa' => link_wa(cliente.telefone, texto)
    )
  end

  def status_email(cliente, novidade, recebeu_email)
    return 'Já recebeu por e-mail hoje.' if recebeu_email
    return 'Não recebeu: etapa delicada (sem e-mail automático).' if novidade['delicada']
    return 'Não recebeu: etapa sem e-mail automático.' if novidade['email'] == false

    cliente.email.blank? ? 'Não recebeu: cliente sem e-mail cadastrado. O seu WhatsApp é o único aviso.' : 'Não recebeu e-mail.'
  end

  def texto_whatsapp(cliente, novidade)
    corpo = if novidade['delicada']
              "Temos uma atualização no seu caso e nossa equipe gostaria de conversar com você.\n" \
                'Qual o melhor horário para ligarmos?'
            else
              "Passando para avisar que há uma novidade no seu caso: #{novidade['titulo']}.\n" \
                "Você pode ver os detalhes no Painel do Cliente: #{link_painel}\n(é só entrar com o seu CPF e a sua senha).\n" \
                'Qualquer dúvida, é só responder aqui.'
            end
    "Olá, #{cliente.primeiro_nome}! Tudo bem? Aqui é a Gabriela, do escritório Ramon Antonio Advogados.\n#{corpo}"
  end

  def link_wa(telefone, texto)
    return if telefone.blank?

    fone = telefone.start_with?('55') && telefone.size > 11 ? telefone : "55#{telefone}"
    "https://wa.me/#{fone}?text=#{ERB::Util.url_encode(texto)}"
  end

  def link_painel = ENV.fetch('PORTAL_URL', "#{ENV.fetch('FRONTEND_URL', nil)}/cliente")

  # "AUXÍLIO-ACIDENTE - ACIDENTÁRIO (B94)" → "auxílio-acidente - acidentário"
  def tipo_amigavel(tipo) = tipo.to_s.sub(/\s*\([^)]*\)\s*\z/, '').downcase
end
