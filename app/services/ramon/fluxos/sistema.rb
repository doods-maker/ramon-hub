# Fluxos do sistema (spec §8, D7; decisão do Eduardo 06/10: as 29 automações do código): o desenho
# só-leitura de cada automação que ainda roda no código. Fonte = db/seeds/ramon/fluxos/sistema/<chave>.json
# ({nome, grupo, alcance?, descricao, limite_dia?, desenho}). Cada conta tem 1 Fluxo origem 'sistema' por
# arquivo (sistema_chave = nome do arquivo), criado ou atualizado quando a lista abre. O motor nunca os
# executa (Fluxo.executaveis e Disparo#iniciar) e a API recusa editar, publicar, ensaiar e rodar.
module Ramon::Fluxos::Sistema
  PASTA = Rails.root.join('db/seeds/ramon/fluxos/sistema')
  CAMPOS = %w[nome descricao limite_dia rascunho].freeze
  RETOMADA = 'RASCUNHO (revisar antes de enviar) — retomada%'.freeze # Ramon::FollowUpDraftService#draft_for
  REUNIAO = %w[meeting_scheduled meeting_rescheduled].freeze # Ramon::ReuniaoAgendamento#call / #remarcar

  # "Hoje" da aba Do sistema (spec §7): só onde o código já deixa rastro barato (1 count); sem fonte → nil ("—").
  HOJE = {
    'cadencia' => ->(conta, dia) { conta.lead_notes.where(created_at: dia).where('body LIKE ?', RETOMADA).count },
    'sla_primeira_resposta' => ->(conta, dia) { Ramon::Cadencia.sla_conversations(conta, dia).count },
    'lembretes_reuniao' => ->(conta, dia) { conta.lead_activities.where(kind: REUNIAO, created_at: dia).count },
    'eventos_advbox' => ->(conta, dia) { AdvboxEvent.where(account: conta, status: 'processed', updated_at: dia).count },
    'lead_ganho' => ->(conta, dia) { conta.leads.where(won_at: dia).count },
    'docs_completos' => ->(conta, dia) { conta.leads.where(docs_completos_em: dia).count },
    'contrato_limpo' => ->(conta, dia) { conta.leads.where(contrato_limpo_em: dia).count },
    'copiloto_noturno' => ->(conta, dia) { conta.copilot_suggestions.where(created_at: dia).count },
    'chegada_cliente' => ->(conta, dia) { conta.chegadas.where(escalado_em: dia).count },
    # ponytail: ramon_pecas não tem coluna de publicada-em; conta as publicações INICIADAS hoje (rótulo honesto na tela).
    'publicar_pecas' => ->(conta, dia) { conta.pecas.where(publicacao_iniciada_em: dia).count }
  }.freeze

  module_function

  def desenhos
    @desenhos ||= PASTA.glob('*.json').sort.to_h { |arquivo| [arquivo.basename('.json').to_s, JSON.parse(arquivo.read)] }
  end

  # Chamado pela lista: nada mudou = 1 SELECT. Criar/atualizar sob o lock da conta, rechecando dentro dele:
  # duas abas abertas ao mesmo tempo logo depois do deploy não duplicam. Linha cujo JSON sumiu fica (a B4 decide).
  def sincronizar(account)
    return if em_dia?(account)

    # Dupla checagem: quem esperou o lock já encontra tudo gravado pelo primeiro e não grava de novo.
    account.with_lock { gravar(account) unless em_dia?(account) }
    nil
  end

  def hoje(account, chave)
    HOJE[chave]&.call(account, Time.find_zone!(Fluxo::ZONA).now.all_day)
  end

  # O que a lista e o desenho mostram além das colunas do Fluxo (vem do JSON em memória, sem coluna nova).
  # resumo: frase simples da lista. gatilho_rotulo: quando o gatilho real não existe nos fluxos, o desenho usa o mais próximo e o rótulo diz o real.
  def extras(account, chave)
    desenho = desenhos[chave] || {}
    {
      hoje: hoje(account, chave), grupo: desenho['grupo'], alcance: desenho['alcance'], resumo: desenho['resumo'],
      gatilho_rotulo: Ramon::Fluxos::Grafo.new(desenho['desenho']).gatilho&.dig('config', 'rotulo')
    }
  end

  def em_dia?(account)
    atuais = account.fluxos.where(origem: 'sistema').pluck(:sistema_chave, *CAMPOS).to_h { |chave, *resto| [chave, resto] }
    desenhos.all? { |chave, d| atuais[chave] == atributos(d).values_at(*CAMPOS) }
  end

  def gravar(account)
    existentes = account.fluxos.where(origem: 'sistema').index_by(&:sistema_chave)
    desenhos.each do |chave, d|
      (existentes[chave] || account.fluxos.new(origem: 'sistema', sistema_chave: chave)).update!(atributos(d))
    end
  end

  def atributos(desenho)
    {
      'nome' => desenho['nome'], 'descricao' => desenho['descricao'], 'limite_dia' => desenho['limite_dia'],
      'rascunho' => desenho['desenho'], 'gatilho_tipo' => Ramon::Fluxos::Grafo.new(desenho['desenho']).gatilho&.dig('config', 'tipo')
    }
  end
end
