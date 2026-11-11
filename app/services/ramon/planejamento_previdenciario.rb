# Planejamento previdenciário: corpo do motor, nomes dos arquivos no Drive e a geração do PDF + memória (job).
# Controller e job não sabem de Redis, Drive, nomes de arquivo nem formato do motor.
class Ramon::PlanejamentoPrevidenciario
  XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze
  # tipo do arquivo → mime; o tipo é também a chave em #nomes e no Redis.
  TIPOS = { 'pdf' => 'application/pdf', 'memoria' => XLSX }.freeze
  GERANDO = 'gerando'.freeze
  PRONTO = 'pronto'.freeze
  ERRO = 'erro'.freeze
  NUMEROS_MUDARAM = 'os números mudaram desde o cálculo — calcule de novo'.freeze
  # Espelho de SECOES_EDITAVEIS em app/javascript/dashboard/routes/dashboard/ramon/helpers/planejamentoTextos.js
  # (mudou lá, muda aqui), assim como ITENS_EDITAVEIS: nas listas de itens, só essas chaves são texto livre.
  SECOES_EDITAVEIS = %w[pendencias observacoes_internas pode nao_pode sugestao cenarios melhorias passos conferir documentos].freeze
  ITENS_EDITAVEIS = { 'pendencias' => %w[t p], 'observacoes_internas' => %w[t p], 'cenarios' => %w[lead bom], 'melhorias' => %w[t p] }.freeze

  class << self
    # cnis = lead.cnis; perfil = Hash string-keyed vindo da tela.
    def payload(cnis, perfil, segurado_nome:, data_calculo: nil)
      entrada = cnis['entrada']
      corpo = {
        segurado: entrada['segurado'], competencias: entrada['competencias'], vinculos: entrada['vinculos'],
        perfil: perfil.to_h.compact_blank.merge('segurado_nome' => segurado_nome)
      }
      corpo[:vinculos_detalhe] = cnis['vinculos'] unless cnis['vinculos'].nil?
      # CNIS lido antes do motor novo não traz a lista (o motor trata como vazia).
      corpo[:abaixo_minimo_pos_reforma] = entrada['abaixo_minimo_pos_reforma'] if entrada['abaixo_minimo_pos_reforma'].present?
      corpo[:data_calculo] = data_calculo unless data_calculo.nil?
      cnis_data = data_iso(cnis['uploaded_at'])
      corpo[:cnis_data] = cnis_data if cnis_data
      corpo
    end

    # Textos em rascunho (formas ainda sem aprovação) saem com "RASCUNHO - " para não passar por definitivo.
    def nomes(dados, hoje: Date.current)
      nome = dados['nome'].to_s.gsub(%r{[/\\:*?"<>|]}, '').squish.presence || 'Sem nome'
      rascunho = dados['formato_textos'] == 'rascunho' ? 'RASCUNHO - ' : ''
      prefixo = dados['turma'].present? ? 'Raio-X Elites' : 'Planejamento previdenciário'
      {
        pasta: "Planejamento previdenciário – #{hoje.strftime('%m.%y')}",
        pdf: "#{rascunho}#{prefixo} - #{nome}.pdf",
        memoria: "#{rascunho}Memória de cálculo - #{nome}.xlsx"
      }
    end

    # tipo: 'pdf' | 'memoria'. nil quando o Redis já expirou (1 h).
    def arquivo(calculo, tipo)
      b64 = Redis::Alfred.get(chave(calculo, tipo))
      Base64.strict_decode64(b64) if b64
    end

    def chave(calculo, tipo) = "ramon:planejamento:#{calculo.id}:#{tipo}"

    private

    def data_iso(valor)
      Date.parse(valor.to_s).iso8601 if valor.present?
    rescue Date::Error
      nil
    end
  end

  def initialize(calculo)
    @calculo = calculo
  end

  def marcar_gerando! = gravar('estado' => GERANDO)

  # Nomes do Drive e do download: do dados salvo, com o mês do cálculo.
  def nomes = self.class.nomes(dados, hoje: @calculo.created_at.to_date)

  # Download: nil quando o Redis já expirou.
  def download(tipo)
    bytes = self.class.arquivo(@calculo, tipo)
    { bytes: bytes, nome: nomes[tipo.to_sym], mime: TIPOS.fetch(tipo) } if bytes
  end

  # Nunca levanta: todo erro vira snapshot['geracao'] com estado ERRO (o job não tem retry).
  def gerar!
    resposta = Ramon::MotorClient.planejamento_previdenciario(payload_do_recalculo)
    # Trava: a memória sai do recálculo; se ele não é o dados da tela (fora os textos editáveis), PDF e memória divergiriam.
    return gravar('estado' => ERRO, 'erro' => NUMEROS_MUDARAM) if sem_textos(resposta['dados']) != sem_textos(dados)

    arquivos = { 'pdf' => Ramon::MotorClient.planejamento_previdenciario_pdf(dados),
                 'memoria' => Base64.strict_decode64(resposta.fetch('memoria_xlsx_b64')) }
    guardar(arquivos)
    gravar({ 'estado' => PRONTO }.merge(salvar_no_drive(arquivos)))
  rescue Ramon::MotorClient::UnavailableError, Ramon::MotorClient::ValidationError => e
    gravar('estado' => ERRO, 'erro' => e.message)
  rescue StandardError => e
    Rails.logger.error("[planejamento] cálculo #{@calculo.id} não gerou: #{e.class} #{e.message}")
    gravar('estado' => ERRO, 'erro' => "não deu para gerar: #{e.class}")
  end

  private

  def parametros_salvos = @calculo.snapshot['params']

  def dados = parametros_salvos['dados']

  def payload_do_recalculo
    data_calculo = Date.strptime(dados['calculo_data'], '%d/%m/%Y').iso8601
    self.class.payload(@calculo.snapshot['cnis'], parametros_salvos['perfil'] || {}, segurado_nome: dados['nome'], data_calculo: data_calculo)
  end

  # O dados com cada texto editável trocado por :texto; o resto (números, datas, estrutura, textos do motor) tem de bater.
  # Integer e Float iguais comparam iguais (1518 == 1518.0): o JSON do front perde o ".0".
  def sem_textos(dados_motor)
    dados_motor.to_h do |secao, valor|
      next [secao, valor] unless SECOES_EDITAVEIS.include?(secao)

      chaves = ITENS_EDITAVEIS[secao]
      next [secao, valor.map { |item| item_sem_textos(item, chaves) }] if chaves && valor.is_a?(Array)

      [secao, mascarar(valor)]
    end
  end

  def item_sem_textos(item, chaves)
    return item unless item.is_a?(Hash)

    item.to_h { |k, v| [k, chaves.include?(k) ? mascarar(v) : v] }
  end

  def mascarar(valor)
    case valor
    when String then :texto
    when Array then valor.map { |v| mascarar(v) }
    when Hash then valor.transform_values { |v| mascarar(v) }
    else valor
    end
  end

  # Redis (não Rails.cache): web e worker são containers diferentes e o cache de produção é arquivo local.
  def guardar(arquivos)
    arquivos.each { |tipo, bytes| Redis::Alfred.setex(self.class.chave(@calculo, tipo), Base64.strict_encode64(bytes), 1.hour) }
  end

  def salvar_no_drive(arquivos)
    lead = @calculo.lead
    return { 'drive' => nil, 'drive_motivo' => 'sem_cliente' } if lead.contact.blank?
    return { 'drive' => nil, 'drive_motivo' => 'drive_desligado' } unless Ramon::DriveClient.configured?

    nome = nomes
    pasta = Ramon::DriveClient.ensure_folder(nome[:pasta], Ramon::DriveExportService.new(lead).pasta_cliente_id)
    arquivos.each do |tipo, bytes|
      Ramon::DriveClient.substituir(name: nome[tipo.to_sym], io: StringIO.new(bytes), content_type: TIPOS.fetch(tipo), parent_id: pasta)
    end
    { 'drive' => { 'pasta_url' => "https://drive.google.com/drive/folders/#{pasta}" } }
  rescue StandardError => e
    Rails.logger.warn("[planejamento] cálculo #{@calculo.id} não salvou no Drive: #{e.class} #{e.message}")
    { 'drive' => nil, 'drive_erro' => "não salvou no Drive: #{e.message.truncate(200)}" }
  end

  def gravar(geracao)
    @calculo.update!(snapshot: @calculo.snapshot.merge('geracao' => geracao))
  end
end
