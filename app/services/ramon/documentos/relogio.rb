# Relógio da cobrança da etapa Documentos (spec Etapa Documentos §7): função pura. Dado o estado gravado no lead
# (custom_attributes['documentos_cobranca'] + a última mensagem do cliente), o agora e a janela de horário dos fluxos, diz qual
# passo venceu. Não lê banco nem envia nada (isso é do Ramon::Documentos::CobrancaJob). Duas fases:
# - o cliente não respondeu desde que entrou: abertura → lembrete 1 (3 h úteis) → lembrete 2 (manhã do dia útil seguinte ao
#   lembrete 1) → silêncio (4 h úteis depois) e mais nada: teto de 2 lembretes até uma pessoa agir;
# - respondeu (mensagem ou documento novo; a resposta zera o silêncio): sem documento novo desde a última cobrança ou o último
#   documento, acompanhamento com 1 dia útil e travado com 2. Documento novo recomeça a contagem.
# Só vence em horário comercial: o cliente que escreve às 23h é respondido pela IA (Perfil da IA), a cobrança espera.
# Números e horário em config/ramon/documentos_cobranca.yml.
# ponytail: sem feriados — Ramon::Fluxos::Horario não tem calendário, feriado conta como dia útil; o calendário entra lá, para todos.
module Ramon::Documentos::Relogio
  CHAVE = 'documentos_cobranca'.freeze
  CONFIG = YAML.safe_load_file(Rails.root.join('config/ramon/documentos_cobranca.yml')).freeze
  RITMO = CONFIG.fetch('ritmo').freeze
  # As marcas do silêncio e a do documento: a contagem do "sem documento novo" parte da mais recente.
  REFERENCIAS = %w[abertura_em lembrete_1_em lembrete_2_em silencio_em ultimo_documento_em].freeze

  module_function

  # estado: entrou_em, ultima_resposta_em, ultimo_documento_em e as marcas de cada passo (<passo>_em), em ISO 8601.
  # @return [Hash{passo: Symbol, em: Time}, nil] o passo que já venceu (em <= agora) quando agora é horário comercial
  def proximo_passo(estado:, agora:, horario: CONFIG['horario'])
    est = ler(estado)
    return unless est['entrou_em'] && Ramon::Fluxos::Horario.comercial?(agora, horario)

    passo = respondeu?(est) ? sem_documento(est, horario) : sem_resposta(est, horario)
    passo if passo && passo[:em] <= agora
  end

  def ler(estado) = estado.to_h.transform_values { |valor| valor.presence && Time.zone.parse(valor.to_s) }

  def respondeu?(est)
    resposta = est.values_at('ultima_resposta_em', 'ultimo_documento_em').compact.max
    resposta.present? && resposta > est['entrou_em']
  end

  def sem_resposta(est, horario)
    return { passo: :abertura, em: Ramon::Fluxos::Horario.proximo(est['entrou_em'], horario) } unless est['abertura_em']
    return if est['silencio_em']
    return { passo: :lembrete_1, em: somar(est['abertura_em'], RITMO['lembrete_1_horas'], horario) } unless est['lembrete_1_em']
    return { passo: :lembrete_2, em: manha_seguinte(est['lembrete_1_em'], horario) } unless est['lembrete_2_em']

    { passo: :silencio, em: somar(est['lembrete_2_em'], RITMO['silencio_horas'], horario) }
  end

  def sem_documento(est, horario)
    ref = est.values_at(*REFERENCIAS).compact.max || est['entrou_em']
    return if est['travado_em'] && est['travado_em'] >= ref

    dia = horas_do_dia(horario)
    if est['acompanhamento_em'].nil? || est['acompanhamento_em'] < ref
      { passo: :acompanhamento, em: somar(ref, RITMO['acompanhamento_dias'] * dia, horario) }
    else
      { passo: :travado, em: somar(ref, RITMO['travado_dias'] * dia, horario) }
    end
  end

  # momento + N horas úteis: só conta o tempo dentro da janela; o que sobra no fim do dia passa para o próximo dia útil.
  def somar(momento, horas, horario)
    fim_hora = Ramon::Fluxos::Horario.janela(horario)[:fim]
    t = Ramon::Fluxos::Horario.proximo(momento, horario).in_time_zone(Ramon::Fluxos::Horario::ZONA)
    resto = horas * 3600
    loop do
      fim = t.beginning_of_day + fim_hora.hours
      return t + resto if resto < fim - t

      resto -= fim - t
      t = Ramon::Fluxos::Horario.proximo(fim, horario)
    end
  end

  def manha_seguinte(momento, horario)
    Ramon::Fluxos::Horario.proximo(momento.in_time_zone(Ramon::Fluxos::Horario::ZONA).beginning_of_day + 1.day, horario)
  end

  def horas_do_dia(horario)
    janela = Ramon::Fluxos::Horario.janela(horario)
    janela[:fim] - janela[:inicio]
  end
end
