# Painel dos agentes: o foreman-vision da esteira, dentro do hub (ADR 0013). Lê transcripts
# com dado de cliente, então só entra quem está em RAMON_PAINEL_AGENTES_EMAILS. Sem a env, ninguém entra.
module Ramon::PainelAgentes
  module_function

  COOKIE = 'cw_d_session_info'.freeze

  # Endereço do painel para esta pessoa; nil = sem acesso (o menu nem aparece).
  def url_para(user)
    ENV['RAMON_PAINEL_AGENTES_URL'].presence if liberado?(user)
  end

  # O Caddy pergunta isto a cada requisição ao painel, com o cookie de sessão do hub.
  def sessao_liberada?(cookie)
    dados = JSON.parse(cookie.to_s)
    return false unless dados.is_a?(Hash) && dados['uid'].is_a?(String)

    user = User.find_by(uid: dados['uid'])
    user.present? && user.valid_token?(dados['access-token'].to_s, dados['client'].to_s) && liberado?(user)
  rescue JSON::ParserError
    false
  end

  def liberado?(user)
    ENV.fetch('RAMON_PAINEL_AGENTES_EMAILS', '').split(',').map { |email| email.strip.downcase }.include?(user&.email&.downcase)
  end
end
