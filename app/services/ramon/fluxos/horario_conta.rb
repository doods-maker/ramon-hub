# B5-conta (spec §8, decisão do Eduardo 07/10): gatilho "Horário da conta" — o alvo é a própria conta, não um lead.
# Config: 'hora' (HH:MM — uma vez por dia a partir dela) OU 'a_cada_minutos' (1–1440); 'dias' (0 = domingo … 6 = sábado;
# sem a chave = todos). Fuso de São Paulo. Chamado a cada minuto pelo Ramon::FluxoRelogioJob.
# A vez é reivindicada ANTES de rodar, num UPDATE condicional em ultimo_disparo_em (o "reivindicar o dia" da B4.3):
# - por dia: 1 vez no dia; fluxo que nasceu depois da hora de hoje começa amanhã (nunca repete a vez que o código já fez);
# - a cada N min: 1 vez por bloco de N minutos.
# O job do código (Ramon::Fluxos::Rotinas::Conta.cada_conta — hoje só o Resumo do dia) disputa a MESMA vez do fluxo
# migrado: quem pega faz. No comando o fluxo faz; não começou ou fora do comando, o código faz.
module Ramon::Fluxos::HorarioConta
  GATILHO = 'horario_conta'.freeze
  PASSOS = %w[se escolha esperar parar avisar_push rotina].freeze # os que rodam sem lead
  # Gatilhos sem lead → alvo: a conta (Horário da conta) ou o registro de um evento de fora do funil (B5-externos —
  # FluxoExecucao.lead_de não dá lead). Neles só entram os PASSOS, e só rotina do mesmo alvo.
  SEM_LEAD_ALVOS = { GATILHO => 'conta' }.merge(
    %w[assinatura_painel documento_painel chegada_cliente reuniao_gravada peca_publicada peca_mudou_status].index_with('outro')
  ).freeze
  DIAS = (0..6).to_a.freeze
  INTERVALO = (1..1440)
  QUANDO = 'O Horário da conta precisa de uma hora (HH:MM) ou de "a cada N minutos" (1 a 1440), e de pelo menos um dia'.freeze
  SEM_LEAD = 'precisa de um lead — neste gatilho só entram Se, Escolha, Esperar, Parar, Push e Rotina pronta'.freeze

  module_function

  def disparar(agora = Time.find_zone!(Fluxo::ZONA).now)
    Fluxo.executaveis.where(gatilho_tipo: GATILHO).includes(:versao_publicada).find_each do |fluxo|
      disparar_fluxo(fluxo, agora)
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: fluxo.account).capture_exception
      Rails.logger.warn("[Ramon::Fluxos::HorarioConta] fluxo #{fluxo.id}: #{e.class}")
    end
  end

  def disparar_fluxo(fluxo, agora)
    return unless na_hora?(config(fluxo), agora) && tem_o_que_fazer?(fluxo) && reivindicar(fluxo, agora)
    return Ramon::Fluxos::Rotinas::Conta.decidir(fluxo) if Ramon::Fluxos::Rotinas::Conta.migrado?(fluxo) # B5: a vez é da rotina
    return if fluxo.modo == 'normal' && fluxo.limite_atingido?

    Ramon::Fluxos::Disparo.new(fluxo, fluxo.account, {}, nil).iniciar
  end

  def config(fluxo) = Ramon::Fluxos::Grafo.new(fluxo.versao_publicada&.grafo).gatilho&.dig('config') || {}

  def na_hora?(config, agora)
    return false unless dias(config).include?(agora.wday)

    intervalo(config).present? || agora >= hora_de_hoje(config, agora)
  end

  # ponytail: o predicado "por dia" repete o de Ramon::Fluxos::Relogio.reivindicar_dia (B4.3), de propósito para não
  # mexer na B4.3 — 2 lugares com a mesma regra; unificar aqui se o relógio dos leads for revisto.
  def reivindicar(fluxo, agora)
    config = config(fluxo)
    n = intervalo(config)
    vez = Fluxo.where(id: fluxo.id)
    vez = if n
            vez.where('ultimo_disparo_em IS NULL OR ultimo_disparo_em < ?', agora.beginning_of_minute - (n - 1).minutes)
          else
            vez.where(created_at: ...hora_de_hoje(config, agora))
               .where('ultimo_disparo_em IS NULL OR ultimo_disparo_em < ?', agora.beginning_of_day)
          end
    vez.update_all(ultimo_disparo_em: agora) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

  # Rotinas que dizem "nada a fazer" (Rotinas.pendente == false) em TODOS os passos rotina: o fluxo nem começa (nem gasta a vez).
  def tem_o_que_fazer?(fluxo)
    nomes = Ramon::Fluxos::Grafo.new(fluxo.versao_publicada.grafo).nos.select { |n| n['tipo'] == 'rotina' }.map { |n| n.dig('config', 'rotina') }
    nomes.empty? || nomes.any? { |nome| Ramon::Fluxos::Rotinas.pendente(nome, fluxo.account) != false }
  end

  def dias(config) = config.key?('dias') ? Array(config['dias']).map(&:to_i) : DIAS

  def intervalo(config) = config['a_cada_minutos'].presence&.to_i

  def hora_de_hoje(config, agora)
    hora, minuto = (config['hora'].presence || '00:00').split(':').map(&:to_i)
    agora.change(hour: hora, min: minuto)
  end

  # Publicar (Grafo#erros): o "quando" do Horário da conta; nos gatilhos sem lead, só os passos que rodam sem lead;
  # em todos, a rotina do alvo certo.
  def erros(grafo)
    gatilho = grafo.gatilho || {}
    tipo = gatilho.dig('config', 'tipo')
    erros = tipo == GATILHO && !quando_valido?(gatilho['config']) ? [QUANDO] : []
    erros + grafo.nos.flat_map { |passo| erros_no(passo, SEM_LEAD_ALVOS[tipo]) }
  end

  def quando_valido?(config)
    n = config['a_cada_minutos']
    ok = n.present? ? n.to_s.match?(/\A\d+\z/) && INTERVALO.cover?(n.to_i) : config['hora'].present?
    ok && (!config.key?('dias') || (dias(config).any? && (dias(config) - DIAS).empty?))
  end

  # alvo = 'conta' | 'outro' (gatilho sem lead) | nil (lead/conversa)
  def erros_no(passo, alvo)
    return [] if passo['tipo'] == 'gatilho'
    return ["Passo #{passo['id']}: #{SEM_LEAD}"] if alvo && PASSOS.exclude?(passo['tipo'])

    nome = passo.dig('config', 'rotina')
    passo['tipo'] == 'rotina' && nome.present? ? erros_rotina(passo['id'], nome, alvo) : []
  end

  def erros_rotina(id, nome, alvo_gatilho)
    alvo = Ramon::Fluxos::Rotinas.alvo(nome)
    return ["Passo #{id}: rotina desconhecida (#{nome})"] if alvo.nil?
    return [] if (SEM_LEAD_ALVOS.value?(alvo) ? alvo : nil) == alvo_gatilho

    if alvo_gatilho == 'conta'
      ["Passo #{id}: esta rotina não é da conta (precisa de um lead ou de outro evento) — não roda no Horário da conta"]
    elsif alvo == 'conta'
      ["Passo #{id}: esta rotina é da conta toda — só roda no gatilho Horário da conta"]
    else
      ["Passo #{id}: esta rotina é de outro alvo (lead ou evento de fora do funil) — não roda neste gatilho"]
    end
  end
end
