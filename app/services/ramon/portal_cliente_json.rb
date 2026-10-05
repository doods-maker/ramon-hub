# JSON da tela "Painel do cliente" do hub: linha da lista, detalhe do cliente
# aberto e o funil do piloto. Só leitura — quem muda é o controller.
module Ramon::PortalClienteJson
  CAMPOS = %w[id nome cpf email telefone advbox_customer_id dias_acesso
              convidado_em termos_aceitos_em sincronizado_em ultimo_acesso_em suspenso_em].freeze
  HISTORICO = 20

  module_function

  def linha(cliente)
    cliente.as_json(only: CAMPOS).merge(
      'processos' => cliente.processos.map { |p| p.slice('id', 'numero', 'tipo', 'etapa', 'fase', 'docs_pendentes') },
      'envios_count' => cliente.envios.count, 'assinaturas_pendentes' => cliente.assinaturas.pendentes.count
    )
  end

  def detalhe(cliente)
    linha(cliente).merge(
      'recados' => cliente.recados,
      'processos' => cliente.processos.map { |p| processo(p) },
      'envios' => cliente.envios.order(created_at: :desc).map { |e| envio(e) },
      'assinaturas' => cliente.assinaturas.order(created_at: :desc).map { |a| a.as_json(only: %w[id nome status assinado_em created_at]) },
      'eventos' => eventos(cliente)
    )
  end

  # cliente_ve = o título que o Painel do Cliente mostra (mesma tradução do portal,
  # Ramon::PortalTexto). Etapa interna: o cliente segue vendo a anterior, sem aviso.
  def processo(proc)
    proc.slice('id', 'numero', 'tipo', 'etapa', 'fase', 'docs_pendentes').merge(
      'cliente_ve' => Ramon::PortalTexto.etapa(PortalCliente.etapa_cliente(proc))['titulo'],
      'etapa_interna' => Ramon::PortalTexto.interna?(proc['etapa'])
    )
  end

  def envio(envio) = envio.as_json(only: %w[id item lawsuit_id drive_file_id advbox_post_id created_at])

  # Histórico do hub (quem fez o quê), mais recente primeiro.
  def eventos(cliente)
    cliente.eventos.includes(:user).order(created_at: :desc, id: :desc).limit(HISTORICO).map do |ev|
      ev.as_json(only: %w[id acao detalhe created_at]).merge('user_name' => ev.user&.name)
    end
  end

  # Funil do piloto + documentos (pedidos em aberto no espelho × enviados pelo painel).
  def metricas(clientes)
    convidados = clientes.select(&:convidado_em)
    ids = convidados.map(&:id)
    envios = PortalEnvio.where(portal_cliente_id: ids)
    funil(convidados).merge(
      enviaram: envios.distinct.count(:portal_cliente_id),
      assinaram: PortalAssinatura.where(portal_cliente_id: ids, status: 'signed').distinct.count(:portal_cliente_id),
      docs_pedidos: convidados.sum { |c| c.processos.sum { |p| Array(p['docs_pendentes']).size } },
      docs_enviados: envios.count
    )
  end

  def funil(convidados)
    { convidados: convidados.size, entraram: convidados.count { |c| c.dias_acesso.positive? },
      voltaram: convidados.count { |c| c.dias_acesso >= 2 } }
  end
end
