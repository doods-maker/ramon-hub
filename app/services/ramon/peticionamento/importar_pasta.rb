# Baixa a pasta do Drive para dentro da petição (pacote em ordem, peça principal lida pelo Claude) e grava `leitura`.
# Erro de Drive/storage sobe (o job tenta de novo); falha do LLM é absorvida por LerPeca e vira aviso.
class Ramon::Peticionamento::ImportarPasta
  CPF = /(?<!\d)(?:\d{3}\.\d{3}\.\d{3}-\d{2}|\d{11})(?!\d)/
  Dados = Ramon::Peticionamento::DadosDaLeitura
  Drive = Ramon::DriveClient

  def self.call(peticao) = new(peticao).call

  def initialize(peticao)
    @peticao = peticao
    @releitura = peticao.leitura&.key?('campos') # leitura anterior: o que o advogado editou não é sobrescrito
  end

  def call
    limpar_pacote
    regras = Ramon::Peticionamento::RegrasDaPasta.call(Drive.conteudo_da_pasta(@peticao.drive_pasta_id))
    return gravar(regras.recusas, regras.avisos, {}, [], nil) if regras.recusas.any?

    bytes = baixar(regras.arquivos)
    principal = @peticao.arquivos.find_by(principal: true)
    avisos = regras.avisos
    campos = Ramon::Peticionamento::LerPeca.call(principal, account: @peticao.account)
    recusas = marcadores(bytes, campos, avisos)
    incertos = aplicar(campos, principal, avisos)
    gravar(recusas, avisos, campos, incertos, cpf_da_pasta)
  end

  private

  # Reler substitui o pacote.
  def limpar_pacote
    @peticao.arquivos.destroy_all
    @peticao.arquivos.reset
  end

  # Devolve os bytes da peça principal (primeiro arquivo).
  def baixar(arquivos)
    arquivos.each_with_index.map do |a, i|
      bytes, = Drive.download(a[:id])
      Ramon::Peticionamento::AdicionarArquivo.call(@peticao, bytes: bytes, nome: a[:nome_limpo], content_type: a[:mime_type],
                                                             origem: 'drive', drive_origem_id: a[:id], principal: i.zero?,
                                                             tipo: ('peticao' if i.zero?))
                                             .update_columns(drive_file_id: a[:id]) # rubocop:disable Rails/SkipsModelValidations
      bytes
    end.first
  end

  # PDF escaneado não tem texto: vale o que o LLM achou (e, se ele falhou, não há verificação nenhuma).
  def marcadores(bytes, campos, avisos)
    avisos << 'leitura_falhou' if campos['falhou']
    texto = Ramon::Peticionamento::MarcadoresRascunho.texto_do_pdf(bytes)
    achados = if texto.strip.empty?
                avisos << 'sem_texto'
                campos['marcadores']
              else
                Ramon::Peticionamento::MarcadoresRascunho.no_texto(texto)
              end
    achados.map { |m| "marcador:#{m}" }
  end

  # Grava na petição só o que foi lido com certeza; devolve os campos incertos.
  def aplicar(campos, principal, avisos)
    if campos['e_peticao'] == false
      avisos << 'nao_parece_peticao'
      @peticao.arquivos.update_all(principal: false) # rubocop:disable Rails/SkipsModelValidations
      return Array(campos['incertos'])
    end

    dados = Dados.call(@peticao.account, campos)
    avisos << 'responsavel_sem_usuario' if dados[:responsavel].nil?
    attrs = dados.slice(:numero_processo, :tribunal, :contact)
    attrs.merge!(dados.slice(:responsavel, :descricao)) unless @releitura
    attrs = attrs.compact
    attrs[:inicial] = dados[:inicial] unless dados[:inicial].nil?
    attrs[:numero_processo] = nil if dados[:inicial]
    @peticao.update!(attrs) # nunca toca em prazo
    principal.update_columns(tipo: 'peticao') # rubocop:disable Rails/SkipsModelValidations
    dados[:incertos]
  end

  def cpf_da_pasta
    Drive.nomes_acima(@peticao.drive_pasta_id).each do |nome|
      achado = CPF.match(nome)
      return achado[0].delete('^0-9') if achado
    end
    nil
  end

  def gravar(recusas, avisos, campos, incertos, cpf)
    @peticao.update!(leitura: { 'estado' => 'lida', 'recusas' => recusas, 'avisos' => avisos.uniq, 'campos' => campos,
                                'incertos' => incertos, 'cpf_pasta' => cpf })
  end
end
