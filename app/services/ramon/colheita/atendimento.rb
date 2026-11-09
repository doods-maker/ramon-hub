# Colheita da IA (custom_attributes['colheita']) -> "00 Atendimento.md": o relato do lead
# para o jurídico. É dado, não prova. Formato fixo em
# docs/superpowers/plans/2026-11-09-atendimento-md.md (Task 2). Saída sempre sem senha.
class Ramon::Colheita::Atendimento
  TZ = 'America/Sao_Paulo'.freeze
  ISO = /\A(\d{4})-(\d{2})-(\d{2})\z/
  FONTE = %r{\A\d{2}/\d{2}\z}
  AVISO = 'É dado, não prova: conferir cada fato com documento antes de usar na peça.'.freeze

  def self.markdown(lead)
    Ramon::Pseudonymizer.sem_senha(new(lead).render)
  end

  def initialize(lead)
    @lead = lead
    colheita = lead.custom_attributes.is_a?(Hash) ? lead.custom_attributes['colheita'] : nil
    @colheita = colheita.is_a?(Hash) ? colheita : {}
    @dados = @colheita['dados'].is_a?(Hash) ? @colheita['dados'] : {}
    @confirmar = Array(@colheita['confirmar']).map(&:to_s)
    @fontes = @colheita['fontes'].is_a?(Hash) ? @colheita['fontes'] : {}
  end

  def render
    corpo = [blocos, trechos, sinais, lacunas].flatten.compact
    corpo = ['Nada colhido da conversa ainda.'] if blocos.empty? && sinais.nil?
    (cabecalho + corpo).join("\n").gsub(/\n{3,}/, "\n\n").rstrip << "\n"
  end

  private

  def cabecalho
    nome = @dados.dig('cliente', 'nome_completo').presence || @lead.name
    ["# Atendimento — #{nome}", '', "> #{origem}", "> #{AVISO}", ''] + metadados + ['']
  end

  def origem
    quando = parse_time(@colheita['extraida_em'])&.strftime('%d/%m/%Y %H:%M')
    "Relato do lead no WhatsApp, extraído pela IA do hub#{" em #{quando}" if quando}."
  end

  def metadados
    [
      ("- **Tese:** #{@lead.thesis.name}" if @lead.thesis),
      periodo && "- **Conversa:** #{periodo}",
      representante && "- **Quem conversou:** #{representante}"
    ].compact
  end

  def periodo
    return if @lead.conversation.blank?

    mensagens = @lead.conversation.messages.where(message_type: [:incoming, :outgoing], private: false)
    primeira = mensagens.minimum(:created_at)
    return if primeira.nil?

    ultima = mensagens.maximum(:created_at)
    "#{data_sp(primeira)} a #{data_sp(ultima)}"
  end

  def representante
    rep = @dados.dig('cliente', 'representante')
    return unless rep.is_a?(Hash) && rep['nome'].present?

    texto = rep['nome'].to_s
    texto += " (#{rep['parentesco']})" if rep['parentesco'].present?
    texto += " — #{rep['motivo']}" if rep['motivo'].present?
    texto
  end

  # --- seções de bloco

  def blocos
    @blocos ||= Ramon::Colheita::Esquema::BLOCOS.keys.excluding('outras_teses_sinal').filter_map do |nome|
      linhas = bloco_linhas(nome, @dados[nome])
      ["## #{humaniza(nome)}", *linhas, ''] if linhas.any?
    end.flatten
  end

  def bloco_linhas(nome, valor)
    if valor.is_a?(Array)
      valor.filter_map { |item| (t = texto(item)).presence && "- #{t}#{marcas(nome)}" }
    elsif valor.is_a?(Hash)
      valor = valor.except('representante') if nome == 'cliente'
      valor.flat_map { |campo, v| campo_linhas("#{nome}.#{campo}", campo, v) }
    else
      []
    end
  end

  def campo_linhas(caminho, campo, valor)
    if valor.is_a?(Array) && valor.any?(Hash)
      itens = valor.filter_map { |item| texto(item).presence }
      return [] if itens.empty?

      ["- #{humaniza(campo)}#{marcas(caminho)}:"] + itens.map { |t| "  - #{t}" }
    else
      t = texto(valor)
      t.empty? ? [] : ["- #{humaniza(campo)}: #{t}#{marcas(caminho)}"]
    end
  end

  def trechos
    itens = Array(@colheita['trechos']).filter_map do |t|
      next unless t.is_a?(Hash) && t['texto'].present?

      "> \"#{t['texto'].to_s.squish}\" — #{caminho_humano(t['campo'])}#{marcas(t['campo'].to_s, confirmar: false)}"
    end
    itens.empty? ? nil : ['## Trechos do relato', *itens, '']
  end

  def sinais
    itens = Array(@dados['outras_teses_sinal']).filter_map do |s|
      next unless s.is_a?(Hash) && s['tese'].present?

      "- #{s['tese']}#{": #{s['motivo']}" if s['motivo'].present?}"
    end
    itens.empty? ? nil : ['## Sinais de outra tese', *itens, '']
  end

  def lacunas
    itens = Array(@colheita['lacunas']).filter_map do |l|
      "- #{caminho_humano(l['campo'])}: #{l['como_obter']}" if l.is_a?(Hash) && l['campo'].present?
    end
    itens.empty? ? nil : ['## O que falta', *itens, '']
  end

  # --- valores

  def texto(valor)
    case valor
    when Array then valor.filter_map { |v| texto(v).presence }.join(valor.any?(Hash) ? '; ' : ', ')
    when Hash then valor.filter_map { |k, v| (t = texto(v)).presence && "#{k.to_s.tr('_', ' ')}: #{t}" }.join(' · ')
    else folha(valor)
    end
  end

  def folha(valor)
    return (valor ? 'sim' : 'não') if [true, false].include?(valor)

    valor.blank? ? '' : valor.to_s.sub(ISO, '\3/\2/\1').tr('_', ' ')
  end

  def humaniza(chave)
    chave.to_s.tr('_', ' ').capitalize
  end

  def caminho_humano(caminho)
    caminho.to_s.gsub(/\[\d+\]/, '').split('.').map { |parte| humaniza(parte) }.join(' · ')
  end

  # "(dd/mm)" se houver fonte válida; "(confirmar)" se o caminho (ou filho) está em confirmar.
  def marcas(caminho, confirmar: true)
    partes = []
    data = fonte(caminho)
    partes << "(#{data})" if data
    partes << '(confirmar)' if confirmar && incerto?(caminho)
    partes.empty? ? '' : " #{partes.join(' ')}"
  end

  def filho?(chave, caminho)
    chave.to_s.start_with?("#{caminho}.", "#{caminho}[")
  end

  def incerto?(caminho)
    @confirmar.any? { |c| c == caminho || filho?(c, caminho) }
  end

  def fonte(caminho)
    valor = @fontes[caminho] || @fontes.find { |chave, _| filho?(chave, caminho) }&.last
    valor if valor.is_a?(String) && valor.match?(FONTE)
  end

  def parse_time(valor)
    Time.zone.parse(valor.to_s)&.in_time_zone(TZ)
  rescue ArgumentError
    nil
  end

  def data_sp(tempo)
    tempo.in_time_zone(TZ).strftime('%d/%m/%Y')
  end
end
