# Horários livres da agenda de um usuário (Closer): grade de 30 em 30 min nas janelas do horário comercial,
# próximos 5 dias úteis sem feriado, 2h de antecedência, 15 min de folga em volta de reuniões do hub e do Google.
# Tudo em America/Sao_Paulo (o Time.zone do app é UTC). Google fora do ar → só a agenda do hub.
class Ramon::Agenda::Disponibilidade
  PASSO = 30.minutes
  FOLGA = 15.minutes
  ANTECEDENCIA = 2.hours
  DIAS_UTEIS = 5

  def self.texto(horarios)
    zona = Time.find_zone!(Ramon::HorarioComercial::TIME_ZONE)
    horarios.group_by { |h| h.in_time_zone(zona).to_date }.map do |_dia, hs|
      dia = Ramon::ReuniaoAgendamento.quando(hs.first).split(' às ').first
      "#{dia} às #{hs.map { |h| h.in_time_zone(zona).strftime('%-H:%M') }.join(' ou ')}"
    end.join('; ')
  end

  def initialize(user:, account:, agora: Time.current)
    @user = user
    @account = account
    @agora = agora
    @zona = Time.find_zone!(Ramon::HorarioComercial::TIME_ZONE)
  end

  def ocupados(de:, ate:) # rubocop:disable Naming/MethodParameterName
    (do_hub(de, ate) + do_google(de, ate)).map { |i, f| (i - FOLGA)...(f + FOLGA) }
  end

  def livres(qtd: 3)
    dias = dias_uteis
    return [] if dias.empty?

    busy = ocupados(de: grade(dias.first, 0, 0), ate: grade(dias.last, 24, 0))
    candidatos(dias).select { |inicio, _| livre_na_grade?(inicio, busy) }.uniq { |_, periodo| periodo }.first(qtd).map(&:first)
  end

  def livre?(inicio)
    inicio = inicio.in_time_zone(@zona)
    dia = inicio.to_date
    return false unless util?(dia) && inicio >= @agora + ANTECEDENCIA
    return false unless janelas(dia).any? { |abre, fecha| inicio >= abre && inicio + PASSO <= fecha }

    livre_na_grade?(inicio, ocupados(de: inicio - 1.day, ate: inicio + 1.day))
  end

  private

  def util?(dia)
    !dia.saturday? && !dia.sunday? && !Ramon::Agenda::Feriados.feriado?(dia)
  end

  def grade(dia, hora, min)
    @zona.local(dia.year, dia.month, dia.day, hora, min)
  end

  def janelas(dia)
    Ramon::HorarioComercial::JANELAS.map { |(hi, mi), (hf, mf)| [grade(dia, hi, mi), grade(dia, hf, mf)] }
  end

  def dias_uteis
    dia = @agora.in_time_zone(@zona).to_date
    dias = []
    while dias.size < DIAS_UTEIS
      dias << dia if util?(dia)
      dia += 1
    end
    dias
  end

  # [[inicio, [dia, meio-período]]...] em ordem cronológica.
  def candidatos(dias)
    dias.flat_map do |dia|
      janelas(dia).each_with_index.flat_map do |(abre, fecha), idx|
        (abre.to_i...fecha.to_i).step(PASSO).map { |t| [@zona.at(t), [dia, idx]] }
                                .select { |ini, _| ini + PASSO <= fecha && ini >= @agora + ANTECEDENCIA }
      end
    end
  end

  def livre_na_grade?(inicio, busy)
    fim = inicio + PASSO
    busy.none? { |r| inicio < r.end && fim > r.begin }
  end

  def do_hub(de, ate) # rubocop:disable Naming/MethodParameterName
    LeadTask.open_tasks.where(kind: 'meeting', agenda_user_id: @user.id, due_at: (de - PASSO)..ate)
            .pluck(:due_at).map { |due| [due, due + PASSO] }
  end

  def do_google(de, ate) # rubocop:disable Naming/MethodParameterName
    conta = GoogleAgendaConta.de(@user)
    return [] unless conta

    Ramon::GoogleAgenda::Cliente.new(conta).eventos(de: de, ate: ate)
                                .reject { |e| e[:cancelado] || e[:inicio].nil? || e[:fim].nil? }.map { |e| [e[:inicio], e[:fim]] }
  rescue Ramon::GoogleAgenda::Cliente::SemConexao, Ramon::GoogleAgenda::Cliente::Erro, Ramon::GoogleAgenda::Token::Transitorio => e
    Rails.logger.warn("[Agenda] Google indisponível (#{e.class}) user_id=#{@user.id}; usando só a agenda do hub")
    []
  end
end
