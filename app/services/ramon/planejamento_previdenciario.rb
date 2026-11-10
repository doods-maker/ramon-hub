# Planejamento previdenciário: corpo do motor, nomes dos arquivos no Drive e a geração do PDF + memória (job).
# Controller e job não sabem de Redis, Drive, nomes de arquivo nem formato do motor.
class Ramon::PlanejamentoPrevidenciario
  XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze
  NUMEROS_MUDARAM = 'os números mudaram desde o cálculo — calcule de novo'.freeze

  class << self
    # cnis = lead.cnis; perfil = Hash string-keyed vindo da tela.
    def payload(cnis, perfil, segurado_nome:, data_calculo: nil)
      entrada = cnis['entrada']
      corpo = {
        segurado: entrada['segurado'], competencias: entrada['competencias'], vinculos: entrada['vinculos'],
        perfil: perfil.to_h.compact_blank.merge('segurado_nome' => segurado_nome)
      }
      corpo[:vinculos_detalhe] = cnis['vinculos'] unless cnis['vinculos'].nil?
      corpo[:data_calculo] = data_calculo unless data_calculo.nil?
      cnis_data = data_iso(cnis['uploaded_at'])
      corpo[:cnis_data] = cnis_data if cnis_data
      corpo
    end

    def nomes(dados, hoje: Date.current)
      nome = dados['nome'].to_s.gsub(%r{[/\\:*?"<>|]}, '').squish.presence || 'Sem nome'
      prefixo = dados['turma'].present? ? 'Raio-X Elites' : 'Planejamento previdenciário'
      {
        pasta: "Planejamento previdenciário – #{hoje.strftime('%m.%y')}",
        pdf: "#{prefixo} - #{nome}.pdf",
        memoria: "Memória de cálculo - #{nome}.xlsx"
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

  # Nunca levanta: todo erro vira snapshot['geracao'] com estado 'erro' (o job não tem retry).
  def gerar!
    resposta = Ramon::MotorClient.planejamento_previdenciario(payload_do_recalculo)
    # Trava: a memória sai do recálculo; se os números dele não são os da tela, PDF e memória divergiriam.
    return gravar('estado' => 'erro', 'erro' => NUMEROS_MUDARAM) if numeros(resposta['dados']) != numeros(dados)

    pdf = Ramon::MotorClient.planejamento_previdenciario_pdf(dados)
    memoria = Base64.strict_decode64(resposta.fetch('memoria_xlsx_b64'))
    guardar('pdf' => pdf, 'memoria' => memoria)
    gravar({ 'estado' => 'pronto' }.merge(salvar_no_drive(pdf, memoria)))
  rescue Ramon::MotorClient::UnavailableError, Ramon::MotorClient::ValidationError => e
    gravar('estado' => 'erro', 'erro' => e.message)
  rescue StandardError => e
    Rails.logger.error("[planejamento] cálculo #{@calculo.id} não gerou: #{e.class} #{e.message}")
    gravar('estado' => 'erro', 'erro' => "não deu para gerar: #{e.class}")
  end

  private

  def params = @calculo.snapshot['params']

  def dados = params['dados']

  def payload_do_recalculo
    data_calculo = Date.strptime(dados['calculo_data'], '%d/%m/%Y').iso8601
    self.class.payload(@calculo.snapshot['cnis'], params['perfil'] || {}, segurado_nome: dados['nome'], data_calculo: data_calculo)
  end

  def numeros(dados_motor)
    [dados_motor.dig('aposentadoria', 'data'), dados_motor['cenarios']&.pluck('rmi'), dados_motor.dig('parar', 'rmi')]
  end

  # Redis (não Rails.cache): web e worker são containers diferentes e o cache de produção é arquivo local.
  def guardar(arquivos)
    arquivos.each { |tipo, bytes| Redis::Alfred.setex(self.class.chave(@calculo, tipo), Base64.strict_encode64(bytes), 1.hour) }
  end

  def salvar_no_drive(pdf, memoria)
    lead = @calculo.lead
    return { 'drive' => nil, 'drive_motivo' => 'sem_cliente' } if lead.contact.blank?
    return { 'drive' => nil, 'drive_motivo' => 'drive_desligado' } unless Ramon::DriveClient.configured?

    nomes = self.class.nomes(dados, hoje: @calculo.created_at.to_date)
    pasta = Ramon::DriveClient.ensure_folder(nomes[:pasta], Ramon::DriveExportService.new(lead).pasta_cliente_id)
    Ramon::DriveClient.substituir(name: nomes[:pdf], io: StringIO.new(pdf), content_type: 'application/pdf', parent_id: pasta)
    Ramon::DriveClient.substituir(name: nomes[:memoria], io: StringIO.new(memoria), content_type: XLSX, parent_id: pasta)
    { 'drive' => { 'pasta_url' => "https://drive.google.com/drive/folders/#{pasta}" } }
  rescue StandardError => e
    Rails.logger.warn("[planejamento] cálculo #{@calculo.id} não salvou no Drive: #{e.class} #{e.message}")
    { 'drive' => nil, 'drive_erro' => "não salvou no Drive: #{e.message}" }
  end

  def gravar(geracao)
    @calculo.update!(snapshot: @calculo.snapshot.merge('geracao' => geracao))
  end
end
