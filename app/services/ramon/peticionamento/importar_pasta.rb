# Baixa a pasta do Drive para dentro da petição (pacote em ordem, peça principal lida pelo Claude) e grava `leitura`.
# Só age com a petição em conferência e `leitura.estado == 'lendo'` (quem enfileira grava `lendo`); confere de novo dentro de cada trava.
# Tudo é baixado antes de mexer no pacote: falha de Drive deixa o pacote antigo inteiro. Erro de Drive/storage sobe (o job tenta de
# novo); falha do LLM é absorvida por LerPeca e vira aviso.
class Ramon::Peticionamento::ImportarPasta
  CPF = /(?<!\d)(?:\d{3}\.\d{3}\.\d{3}-\d{2}|\d{11})(?!\d)/
  Drive = Ramon::DriveClient

  def self.call(peticao) = new(peticao).call

  def initialize(peticao)
    @peticao = peticao
  end

  def call
    @peticao.reload
    return unless lendo?

    @releitura = releitura?
    regras = Ramon::Peticionamento::RegrasDaPasta.call(Drive.conteudo_da_pasta(@peticao.drive_pasta_id))
    return gravar_recusa(regras) if regras.recusas.any?

    baixados = regras.arquivos.map { |a| [a, Drive.download(a[:id]).first] }
    ler(regras.avisos, baixados.first.last) if trocar_pacote(baixados)
  end

  private

  def lendo? = @peticao.conferencia? && @peticao.leitura['estado'] == 'lendo'

  # Releitura só conta se a leitura anterior foi útil (o advogado pode ter editado responsável e descrição).
  def releitura?
    campos = @peticao.leitura['campos']
    campos.present? && campos['falhou'] != true && campos['e_peticao'] != false
  end

  def gravar_recusa(regras)
    @peticao.with_lock do
      next unless lendo?

      limpar_pacote
      gravar(regras.recusas, regras.avisos, {}, [], nil)
    end
  end

  # Troca o pacote inteiro numa trava só; false se a petição mudou de estado no meio.
  def trocar_pacote(baixados)
    @peticao.with_lock do
      next false unless lendo?

      limpar_pacote
      baixados.each_with_index { |(a, bytes), i| adicionar(a, bytes, i.zero?) }
      true
    end
  end

  def limpar_pacote
    @peticao.arquivos.destroy_all
    @peticao.arquivos.reset
  end

  def adicionar(arquivo, bytes, primeiro)
    Ramon::Peticionamento::AdicionarArquivo.call(@peticao, bytes: bytes, nome: arquivo[:nome_limpo], content_type: arquivo[:mime_type],
                                                           origem: 'drive', drive_origem_id: arquivo[:id], principal: primeiro,
                                                           tipo: ('peticao' if primeiro))
                                           .update_columns(drive_file_id: arquivo[:id]) # rubocop:disable Rails/SkipsModelValidations
  end

  # O LLM precisa do arquivo já anexado: por isso a leitura vem depois da troca, em outra trava.
  def ler(avisos, bytes)
    campos = Ramon::Peticionamento::LerPeca.call(@peticao.arquivos.find_by(principal: true), account: @peticao.account)
    avisos << 'leitura_falhou' if campos['falhou']
    recusas = marcadores(bytes, campos, avisos)
    cpf = cpf_da_pasta
    @peticao.with_lock do
      next unless lendo?

      incertos = aplicar(campos, avisos)
      gravar(recusas, avisos, campos, incertos, cpf)
    end
  end

  # PDF escaneado não tem texto: vale o que o LLM achou (e, se ele falhou, não há verificação nenhuma).
  def marcadores(bytes, campos, avisos)
    texto = Ramon::Peticionamento::MarcadoresRascunho.texto_do_pdf(bytes)
    achados = if texto.strip.empty?
                avisos << 'sem_texto'
                campos['marcadores']
              else
                Ramon::Peticionamento::MarcadoresRascunho.no_texto(texto)
              end
    achados.map { |m| "marcador:#{m}" }
  end

  # Grava na petição só o que veio não-nil (releitura: o que o advogado editou fica); devolve os campos incertos.
  def aplicar(campos, avisos)
    if campos['e_peticao'] == false
      avisos << 'nao_parece_peticao'
      @peticao.arquivos.update_all(principal: false) # rubocop:disable Rails/SkipsModelValidations
      return Array(campos['incertos'])
    end

    dados = Ramon::Peticionamento::DadosDaLeitura.call(@peticao.account, campos)
    avisos << 'responsavel_sem_usuario' if dados[:responsavel].nil?
    attrs = dados.slice(:numero_processo, :tribunal, :contact)
    attrs.merge!(dados.slice(:responsavel, :descricao)) unless @releitura
    attrs = attrs.compact
    attrs[:inicial] = dados[:inicial] unless dados[:inicial].nil?
    attrs[:numero_processo] = nil if dados[:inicial]
    @peticao.update!(attrs) # nunca toca em prazo
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
