# Painel do CLIENTE na caixa do escritório (redesign v2): quem é, desde quando,
# advogada responsável, processos e o próximo compromisso — sem chamar o ADVBOX
# por conversa (vem do espelho PortalCliente + caches de usuários e da semana).
# ADVBOX fora zera só o compromisso/sugestão; o resto vem do espelho.
class Ramon::ClienteDaConversa
  ERROS_ADVBOX = [Ramon::AdvboxClient::UnavailableError, Ramon::AdvboxClient::RequestError].freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def perform
    cliente = portal_cliente
    return { cliente: false } unless cliente

    processos = Array(cliente.processos)
    principal = processos.first || {}
    advogada = sugestao(principal)
    {
      cliente: true, nome: cliente.nome, desde: desde(processos), telefone: @conversation.contact.phone_number,
      advogada: { nome: advogada&.name || principal['responsavel'], user_id: advogada&.id },
      processos: processos.map { |p| processo(p) }, compromisso: compromisso(processos), sugestao_user_id: advogada&.id
    }
  end

  private

  # telefone do espelho é só dígitos, em qualquer grafia (com/sem 55 e 9º dígito).
  def portal_cliente
    variantes = Ramon::Telefone.variantes(@conversation.contact.phone_number)
    return if variantes.empty?

    PortalCliente.where(account_id: @conversation.account_id).find_by(telefone: variantes)
  end

  def desde(processos)
    processos.filter_map { |p| p['inicio'].to_s.to_date }.min&.strftime('%Y-%m')
  end

  def processo(proc)
    ultimo = Array(proc['andamentos']).max_by { |a| a['data'].to_s }
    { numero: proc['numero'], tipo: proc['tipo'], fase: proc['fase'],
      ultimo_andamento: ultimo && { data: ultimo['data'], titulo: ultimo['titulo'] } }
  end

  def sugestao(proc)
    proc['responsavel_id'] && Ramon::AdvboxUsuarios.usuario(@conversation.account, proc['responsavel_id'])
  rescue *ERROS_ADVBOX
    nil
  end

  def compromisso(processos)
    servico = Ramon::SemanaAdvboxService.new(@conversation.account)
    tarefa = processos.filter_map { |p| p['numero'].presence }.flat_map { |numero| servico.tarefas_do_processo(numero) }
                      .select { |t| t[:destaque] }.min_by { |t| [t[:data], t[:hora].to_s] }
    tarefa && { tipo: tarefa[:destaque], data: tarefa[:data], hora: tarefa[:hora], notas: tarefa[:notas] }
  rescue *ERROS_ADVBOX
    nil
  end
end
