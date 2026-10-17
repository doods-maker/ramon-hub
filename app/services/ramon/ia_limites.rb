# Limites gerais do escritório (tela "Como a IA atende", Padrão do escritório): horário comercial, atraso da resposta da IA,
# tetos diários e intervalo da retomada. Moram em account.settings['ia_limites']; ausente = os valores de sempre. Quem usava
# constante lê daqui (de). A escrita valida tudo (fragmento!) e devolve o pedaço de settings — quem grava junta com o
# Perfil da IA num account.update! só (Ramon::PerfilIa::Gravacao). O teto em US$ continua na chave do alerta de gasto.
module Ramon::IaLimites
  CHAVE = 'ia_limites'.freeze
  ATRASO_MAXIMO = 180 # segundos; acima disso o cliente acha que a IA sumiu
  ATRASO_PADRAO = { 'min' => 30, 'max' => ATRASO_MAXIMO }.freeze
  INTEIROS = { 'fluxo_ia_dia' => 1..1000, 'retomadas_dia' => 1..1000, 'retomada_intervalo_dias' => 1..60 }.freeze
  HORA = /\A([01]\d|2[0-3]):[0-5]\d\z/

  module_function

  # Os limites em vigor da conta (conta nil = os padrões). Valor salvo inválido (a API grava qualquer coisa no jsonb) cai no padrão.
  def de(account)
    salvo = account&.settings&.dig(CHAVE)
    salvo = {} unless salvo.is_a?(Hash)
    atraso = valido(salvo['atraso'], ATRASO_PADRAO) { |v| atraso!(v) }
    { horario: valido(salvo['horario'], horario_padrao) { |v| horario!(v) }, atraso: atraso['min']..atraso['max'] }
      .merge(INTEIROS.keys.to_h { |k| [k.to_sym, valido(salvo[k], padrao_inteiro(k)) { |v| inteiro!(k, v) }] })
  end

  # Corpo do GET da tela: os limites + o teto em US$ (nil = sem alerta) + o teto do agente @claude (só leitura).
  def corpo(account)
    limites = de(account)
    limites.merge(atraso: { min: limites[:atraso].min, max: limites[:atraso].max },
                  teto_usd: Ramon::IaGastoAlerta.teto(account), agente_dia: AgenteExecucao::TETO_DIA)
  end

  # Valida o que veio da tela (chaves em string; parcial vale) e devolve o fragmento de settings a mesclar. ArgumentError = 422.
  def fragmento!(account, limites)
    raise ArgumentError, 'limites inválidos' unless limites.is_a?(Hash)

    novo = Hash(account.settings&.dig(CHAVE)).merge(validados!(limites))
    fragmento = { CHAVE => novo }
    fragmento[Ramon::IaGastoAlerta::CHAVE_TETO] = teto!(limites['teto_usd']) if limites.key?('teto_usd')
    fragmento
  end

  def gravar!(account, limites)
    account.update!(settings: Hash(account.settings).merge(fragmento!(account, limites)))
  end

  def validados!(limites)
    validos = {}
    validos['horario'] = horario!(limites['horario']) if limites.key?('horario')
    validos['atraso'] = atraso!(limites['atraso']) if limites.key?('atraso')
    INTEIROS.each_key { |k| validos[k] = inteiro!(k, limites[k]) if limites.key?(k) }
    validos
  end

  def horario_padrao
    janelas = Ramon::HorarioComercial::JANELAS.map { |ini, fim| [ini, fim].map { |hm| hm.map { |n| n.to_s.rjust(2, '0') }.join(':') } }
    { 'dias' => Ramon::HorarioComercial::DIAS, 'janelas' => janelas }
  end

  def padrao_inteiro(chave)
    case chave
    when 'fluxo_ia_dia' then ENV.fetch('RAMON_FLUXO_IA_DIA', Ramon::Fluxos::Passos::Ia::TETO_PADRAO).to_i
    when 'retomadas_dia' then Ramon::Fluxos::Retomada::TETO
    else Ramon::Fluxos::Retomada::INTERVALO_DIAS
    end
  end

  def valido(valor, padrao)
    return padrao if valor.nil?

    yield(valor)
  rescue ArgumentError
    padrao
  end

  def horario!(horario)
    raise ArgumentError, 'horário inválido' unless horario.is_a?(Hash)

    dias = horario['dias']
    raise ArgumentError, 'escolha ao menos um dia da semana' unless dias.is_a?(Array) && dias.any?
    raise ArgumentError, 'dia da semana inválido' unless dias.all? { |d| d.is_a?(Integer) && d.between?(0, 6) }

    { 'dias' => dias.uniq.sort, 'janelas' => janelas!(horario['janelas']) }
  end

  # 1 ou 2 faixas "HH:MM", cada uma com início < fim, em ordem e sem encostar na anterior.
  def janelas!(janelas)
    raise ArgumentError, 'informe 1 ou 2 faixas de horário' unless janelas.is_a?(Array) && janelas.size.between?(1, 2)

    minutos = janelas.map { |faixa| faixa!(faixa) }
    raise ArgumentError, 'a faixa da tarde começa depois que a da manhã termina' if minutos.size == 2 && minutos[1][0] < minutos[0][1]

    janelas.map(&:dup)
  end

  def faixa!(faixa)
    raise ArgumentError, 'horário deve ser HH:MM' unless faixa.is_a?(Array) && faixa.size == 2 && faixa.all?(HORA)

    ini, fim = faixa.map { |h| (h[0, 2].to_i * 60) + h[3, 2].to_i }
    raise ArgumentError, 'o início da faixa deve ser antes do fim' unless ini < fim

    [ini, fim]
  end

  def atraso!(atraso)
    raise ArgumentError, 'atraso inválido' unless atraso.is_a?(Hash)

    min, max = atraso.values_at('min', 'max')
    raise ArgumentError, 'atraso: informe mínimo e máximo em segundos' unless [min, max].all?(Integer) && min >= 0
    raise ArgumentError, "atraso máximo é de #{ATRASO_MAXIMO} segundos" if max > ATRASO_MAXIMO
    raise ArgumentError, 'atraso: o mínimo não pode passar do máximo' if min > max

    { 'min' => min, 'max' => max }
  end

  def inteiro!(chave, valor)
    faixa = INTEIROS.fetch(chave)
    raise ArgumentError, "#{chave}: informe um número inteiro de #{faixa.min} a #{faixa.max}" unless valor.is_a?(Integer) && faixa.cover?(valor)

    valor
  end

  # Vazio = sem alerta (nil); senão número >= 0 (aceita vírgula).
  def teto!(valor)
    return if valor.blank?

    teto = valor.is_a?(Numeric) ? valor.to_f : Float(valor.to_s.tr(',', '.'), exception: false)
    raise ArgumentError, 'teto em US$ inválido' if teto.nil? || teto.negative?

    teto
  end
end
