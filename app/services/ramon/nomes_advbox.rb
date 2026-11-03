# Nomes do ADVBOX para a tela de aprovação: mostra a quem a tarefa vai e de que tipo, a partir dos IDs do pedido.
# ADVBOX fora do ar não derruba a tela: sem nome, ela mostra o número.
module Ramon::NomesAdvbox
  module_function

  CHAVE = 'ramon/advbox_nomes_aprovacao'.freeze

  def da_entrada(entrada)
    return {} unless entrada['responsavel_id'] || entrada['tipo_tarefa_id']

    { responsavel: nomes[:usuarios][entrada['responsavel_id'].to_i], tipo: nomes[:tipos][entrada['tipo_tarefa_id'].to_i] }.compact
  end

  def nomes
    Rails.cache.read(CHAVE) || buscar
  end

  def buscar
    cfg = Ramon::AdvboxClient.settings
    guardar({ usuarios: Array(cfg['users']).to_h { |u| [u['id'], u['name']] },
              tipos: Array(cfg['tasks']).to_h { |t| [t['id'], t['task']] } }, 24.hours)
  rescue Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError
    guardar({ usuarios: {}, tipos: {} }, 1.minute) # a tela consulta de 5 em 5 s: não insistir com o ADVBOX fora
  end

  def guardar(valor, validade)
    Rails.cache.write(CHAVE, valor, expires_in: validade)
    valor
  end
end
