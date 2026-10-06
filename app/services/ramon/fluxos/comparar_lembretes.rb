# B4.1 (spec §8, passo 2): lembrete a lembrete, o que o código mandou (rastro 'lembrete' do Ramon::MeetingReminderJob)
# ao lado do que o fluxo "Lembretes de reunião" em sombra diz que mandaria (linhas "faria: sino para …" da trilha).
# Só leitura. Casa pelo lead e pelo horário (até 3 min: o relógio dos fluxos anda de minuto em minuto, o Sidekiq no segundo).
# O lado do código vem do rastro no Redis (Reunioes.rastros), não da tabela de avisos: a deduplicação do Chatwoot
# guarda só o último aviso por pessoa e lead.
class Ramon::Fluxos::CompararLembretes
  JANELA = 3.minutes
  REUNIAO = %w[meeting_scheduled meeting_rescheduled].freeze
  # ponytail: lê o resumo do ensaio de Passos::Aviso#avisar_sino; mudou lá, muda aqui (os specs dos dois pegam)
  PESSOAS = /\Afaria: sino para (.*?): "/
  ROTULOS = { 'igual' => 'igual', 'so_codigo' => 'só no código', 'so_fluxo' => 'só no fluxo',
              'pessoas' => 'pessoas diferentes' }.freeze

  attr_reader :de, :ate

  # Começo honesto: o mais tarde entre (ate - dias), o nascimento dos fluxos e o fim do rastro do código (o Redis guarda
  # 8 dias contados de agora): antes disso o código pode ter avisado e o registro sumido.
  def self.inicio(account, dias, ate)
    [ate - dias.days, Ramon::Fluxos::Reunioes.fluxos(account).minimum(:created_at),
     Time.current - Ramon::Fluxos::Reunioes::RASTRO_RETENCAO].compact.max
  end

  # O período no cabeçalho dos dois relatórios, com o teto da janela.
  def self.periodo(desde, ate)
    logica = Ramon::Fluxos::Passos::Logica
    dias = Ramon::Fluxos::Reunioes::RASTRO_RETENCAO.in_days.to_i
    "#{logica.hora(desde)} até #{logica.hora(ate)} (horário de Brasília; no máximo #{dias} dias: o rastro do código não guarda mais)"
  end

  def initialize(account, dias: 1, ate: Time.current)
    @account = account
    @fluxo = Ramon::Fluxos::Reunioes.fluxo(account, 'lembretes_reuniao') || raise(ArgumentError, 'Os fluxos de reunião ainda não existem')
    @ate = ate
    @de = self.class.inicio(account, dias, ate)
  end

  def linhas
    @linhas ||= begin
      sobra = do_fluxo
      casadas = do_codigo.map { |codigo| casar(codigo, sobra) }
      (casadas + sobra.map { |fluxo| linha('so_fluxo', fluxo, nil, fluxo) }).sort_by { |item| item[:em] }
    end
  end

  def divergencias = linhas.count { |item| item[:situacao] != 'igual' }

  def relatorio = [cabecalho, *linhas.map { |item| texto(item) }, total, resultado].join("\n")

  private

  def casar(codigo, sobra)
    par = sobra.find { |f| f[:lead_id] == codigo[:lead_id] && (f[:em] - codigo[:em]).abs <= JANELA }
    return linha('so_codigo', codigo, codigo, nil) unless par

    sobra.delete(par)
    linha(par[:pessoas] == codigo[:pessoas] ? 'igual' : 'pessoas', codigo, codigo, par)
  end

  def linha(situacao, base, codigo, fluxo)
    { situacao: situacao, em: base[:em], lead_id: base[:lead_id], lead: base[:lead], codigo: codigo, fluxo: fluxo }
  end

  # O sino do código: 1 rastro 'lembrete' por lembrete (lead, rótulo, quem recebeu).
  def do_codigo
    leads = leads_em_sombra
    Ramon::Fluxos::Reunioes.rastros(@account, de, ate).filter_map do |rastro|
      next unless rastro['tipo'] == 'lembrete' && leads.include?(rastro['lead_id'])

      { lead_id: rastro['lead_id'], lead: nome(rastro['lead_id']), em: Time.zone.at(rastro['em']), rotulo: rastro['rotulo'],
        pessoas: User.where(id: rastro['user_ids']).pluck(:name).sort }
    end
  end

  # Só reuniões marcadas/remarcadas depois que a sombra nasceu: as de antes não têm ciclo para comparar.
  def leads_em_sombra
    @account.lead_activities.where(kind: REUNIAO, created_at: @fluxo.created_at..).distinct.pluck(:lead_id)
  end

  # O ensaio: as linhas "faria: sino para …" dos ciclos em sombra ("Testar com um lead…" fica de fora). O alvo é a
  # tarefa (pode ter sido apagada) — o lead vem do gatilho.
  def do_fluxo
    @fluxo.execucoes.where(ensaio: true, updated_at: de..).flat_map do |execucao|
      execucao.contexto['pular_esperas'] ? [] : execucao.trilha.filter_map { |t| do_trilha(execucao, t) }
    end
  end

  def do_trilha(execucao, passo)
    pessoas = passo['tipo'] == 'avisar_sino' && passo['resumo'].to_s[PESSOAS, 1]
    em = Time.zone.parse(passo['em'].to_s)
    return unless pessoas && em && (de..ate).cover?(em)

    lead_id = execucao.contexto.dig('gatilho', 'lead_id') || execucao.lead&.id
    { lead_id: lead_id, lead: nome(lead_id), em: em, rotulo: nil, pessoas: pessoas.split(', ').sort }
  end

  # ponytail: 1 consulta por lead (cacheada); agrupar se o relatório passar de centenas de lembretes.
  def nome(lead_id) = (@nomes ||= {})[lead_id] ||= Lead.find_by(id: lead_id)&.name

  def cabecalho = "Lembretes de reunião — código × fluxo em sombra · conta #{@account.id} · #{self.class.periodo(de, ate)}"

  def texto(item)
    quem = [("código: #{item[:codigo][:pessoas].join(', ')}" if item[:codigo]),
            ("fluxo: #{item[:fluxo][:pessoas].join(', ')}" if item[:fluxo])].compact.join(' · ')
    "#{ROTULOS[item[:situacao]].ljust(18)} #{Ramon::Fluxos::Passos::Logica.hora(item[:em])}  #{item[:lead]} (lead #{item[:lead_id]})  " \
      "#{item.dig(:codigo, :rotulo) || 'lembrete'}  #{quem}"
  end

  def total
    conta = ROTULOS.keys.index_with { |s| linhas.count { |item| item[:situacao] == s } }
    esperando = @fluxo.execucoes.where(ensaio: true, status: 'esperando').count
    "Total: #{linhas.size} lembrete(s) comparado(s) — #{conta['igual']} iguais · #{conta['so_codigo']} só no código · " \
      "#{conta['so_fluxo']} só no fluxo · #{conta['pessoas']} com pessoas diferentes · #{esperando} reunião(ões) com lembrete por vir"
  end

  def resultado
    return 'Resultado: nada para comparar ainda (nenhum lembrete no período)' if linhas.empty?

    divergencias.zero? ? 'Resultado: BATEU' : 'Resultado: NÃO BATEU — veja as linhas que não são "igual"'
  end
end
