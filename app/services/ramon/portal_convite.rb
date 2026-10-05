# Gera a senha provisória do Painel do Cliente e diz como ela chega ao cliente:
# - e-mail de convite, só se houver e-mail E servidor de e-mail (SMTP_ADDRESS) —
#   a resposta diz qual dos três aconteceu (enviado | sem_email | sem_servidor);
# - mensagem pronta pra equipe copiar ou abrir no WhatsApp (wa.me): quem aperta
#   enviar é sempre uma pessoa, nada sai sozinho.
# A mensagem é texto NOVO pro cliente: só aparece com PORTAL_MENSAGEM_CONVITE=on,
# depois do "aprovado" do Eduardo (enquanto isso o hub mostra só a senha).
class Ramon::PortalConvite
  MENSAGEM = <<~TEXTO.freeze
    Olá, %<nome>s! Aqui é do escritório Ramon Antonio Advogados.
    Agora você pode acompanhar o seu caso pelo celular, no Painel do Cliente.

    Para entrar:
    1. Abra: %<url>s
    2. Digite o seu CPF: %<cpf>s
    3. Digite esta senha provisória: %<senha>s

    Depois de entrar, você pode trocar a senha por outra fácil de lembrar (só números). Guarde esta senha e não passe para ninguém.
    Qualquer dúvida, é só responder esta mensagem.
  TEXTO

  def self.email_configurado? = ENV.fetch('SMTP_ADDRESS', nil).present? || Rails.env.development?

  def initialize(cliente)
    @cliente = cliente
  end

  # Data do 1º convite fica: senha nova não reescreve quando o cliente foi convidado.
  def perform
    senha = @cliente.gerar_senha_provisoria!
    @cliente.update!(convidado_em: @cliente.convidado_em || Time.current)
    texto = mensagem(senha)
    { senha_provisoria: senha, email: enviar_email(senha), mensagem: texto, whatsapp_url: whatsapp(texto) }
  end

  private

  def enviar_email(senha)
    return { status: 'sem_email' } if @cliente.email.blank?
    return { status: 'sem_servidor', para: @cliente.email } unless self.class.email_configurado?

    Ramon::PortalMailer.with(account: @cliente.account, cliente: @cliente, senha: senha).convite.deliver_later
    { status: 'enviado', para: @cliente.email }
  end

  def mensagem(senha)
    return unless ENV['PORTAL_MENSAGEM_CONVITE'] == 'on'

    format(MENSAGEM, nome: @cliente.primeiro_nome, url: url_painel, cpf: cpf_formatado, senha: senha).strip
  end

  # Mesmo formato do link_wa do Ramon::PortalAvisosJob: telefone sem DDI ganha o 55.
  def whatsapp(texto)
    fone = @cliente.telefone
    return if texto.blank? || fone.blank?

    fone = "55#{fone}" unless fone.start_with?('55') && fone.size > 11
    "https://wa.me/#{fone}?text=#{ERB::Util.url_encode(texto)}"
  end

  def cpf_formatado = @cliente.cpf.to_s.sub(/\A(\d{3})(\d{3})(\d{3})(\d{2})\z/, '\1.\2.\3-\4')

  def url_painel = ENV.fetch('PORTAL_URL', "#{ENV.fetch('FRONTEND_URL', nil)}/cliente")
end
