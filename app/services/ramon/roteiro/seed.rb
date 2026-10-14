# Seed dos roteiros da tese (spec 2026-10-13 §3.10, F4): db/seeds/ramon/roteiros/*.yml, comuns.yml primeiro.
# Idempotente: passo achado por (tese, chave); editado na tela (edited, F2) fica como está. Tese que falta é criada fora da
# tabela de honorário (a IA não cita valor); `antes:` acha a tese pelo nome antigo e renomeia (D19), sem trocar o id.
# Tudo numa transação: no fim a Conferencia da tela (F2) roda nos passos do seed e qualquer erro desfaz tudo.
# Posições 0-based, como o reorder da tela (F2). ponytail: passo que sai do YAML não é apagado — apaga-se pela tela.
class Ramon::Roteiro::Seed
  DIR = Rails.root.join('db/seeds/ramon/roteiros')
  CAMPOS = %w[titulo orientacao tipo_resposta opcoes calculadora calculadora_campos saidas].freeze
  VAZIO = { 'orientacao' => nil, 'opcoes' => [], 'calculadora' => nil, 'calculadora_campos' => {}, 'saidas' => [] }.freeze

  def initialize(account, dir: DIR)
    @account = account
    @dir = Pathname(dir)
    @contagem = Hash.new(0)
    @passos = []
  end

  # @return [Hash] contagens (teses_criadas, passos_criados/atualizados/pulados_editados, etiquetas_conferidas)
  def run
    ActiveRecord::Base.transaction do
      arquivos.each { |dados| semear(dados) }
      conferir!
      etiquetar
    end
    @contagem
  end

  private

  # comuns.yml primeiro, depois os outros em ordem alfabética.
  def arquivos
    Dir[@dir.join('*.yml').to_s].sort_by { |f| [File.basename(f) == 'comuns.yml' ? 0 : 1, f] }
                                .map { |f| YAML.safe_load_file(f) }
  end

  def semear(dados)
    tese = dados['tese'] && tese_de(dados)
    dados.fetch('passos').each_with_index { |attrs, posicao| semear_passo(tese, attrs, posicao) }
  end

  def tese_de(dados)
    tese = @account.theses.find_by(name: [dados['tese'], *dados['antes']]) ||
           @account.theses.new(area: 'previdenciario', position: @account.theses.maximum(:position).to_i + 1)
    @contagem[:teses_criadas] += 1 if tese.new_record?
    tese.update!(name: dados['tese'])
    tese
  end

  def semear_passo(tese, attrs, posicao)
    passo = RoteiroPasso.find_or_initialize_by(account: @account, thesis: tese, chave: attrs.fetch('chave'))
    @passos << passo
    return @contagem[:passos_pulados_editados] += 1 if passo.edited?

    @contagem[passo.new_record? ? :passos_criados : :passos_atualizados] += 1
    passo.update!(VAZIO.merge(attrs.slice(*CAMPOS)).merge('position' => posicao))
  end

  # "Vai para", campos da calculadora e chaves repetidas: a mesma conferência do salvar da tela (F2).
  def conferir!
    erros = @passos.flat_map { |p| Ramon::Roteiro::Conferencia.erros(p).map { |erro| "#{p.chave}: #{erro}" } }
    raise ArgumentError, "Roteiro com erro (nada foi gravado): #{erros.join('; ')}" if erros.any?
  end

  # Etiquetas das saídas + a do desqualificado (D8): existem na conta para aparecer com cor no hub.
  def etiquetar
    titulos = @passos.flat_map { |p| p.saidas.filter_map { |s| s.dig('efeitos', 'etiqueta')&.downcase } }
    (titulos + [Ramon::Roteiro::Efeitos::ETIQUETA_DESQUALIFICADO]).uniq.each do |titulo|
      Ramon::StageLabelSync.ensure_label(@account, titulo)
      @contagem[:etiquetas_conferidas] += 1
    end
  end
end
