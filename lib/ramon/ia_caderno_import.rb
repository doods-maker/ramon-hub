# FORK-PONTO (ramon): importa o caderno de provas da Inteligência
# (db/seeds/ramon/ia_casos.yml) como Casos de teste da IA. Idempotente: chave =
# codigo dentro do assistente; caso que já existe fica como está (edição na
# tela vale). Sem assistente, importa em cada um do yml que existir na conta.
class Ramon::IaCadernoImport
  ARQUIVO = Rails.root.join('db/seeds/ramon/ia_casos.yml')

  def initialize(account, assistente = nil)
    @account = account
    @assistente = assistente.to_s.strip
    @dados = YAML.safe_load(ARQUIVO.read)
    @contagem = Hash.new(0)
    @inativos = []
  end

  # @return [Hash] contagens + códigos importados como inativos (ambíguos)
  def run
    blocos.each do |bloco|
      assistant = alvo || @account.captain_assistants.find_by(name: bloco['nome'])
      next @contagem[:assistente_ausente] += 1 if assistant.blank?

      bloco['casos'].each { |caso| importar(assistant, caso, bloco['nunca']) }
    end
    @contagem.merge(inativos: @inativos.join(', '))
  end

  private

  def blocos
    todos = @dados.fetch('assistentes')
    return todos if alvo.blank?

    escolhidos = todos.select { |bloco| bloco['nome'] == alvo.name }
    raise ArgumentError, "#{alvo.name} não está no caderno (#{todos.pluck('nome').join(', ')})" if escolhidos.empty?

    escolhidos
  end

  def alvo
    return if @assistente.blank?

    @alvo ||= @account.captain_assistants.find_by(id: Integer(@assistente, exception: false)) ||
              @account.captain_assistants.find_by!(name: @assistente)
  end

  def importar(assistant, caso, nunca)
    registro = Captain::IaCaso.find_or_initialize_by(account_id: @account.id, assistant_id: assistant.id, codigo: caso['codigo'])
    return @contagem[:ja_existiam] += 1 if registro.persisted?

    registro.update!(atributos(caso, nunca))
    @inativos << caso['codigo'] unless registro.ativo
    @contagem[registro.ativo ? :criados_ativos : :criados_inativos] += 1
  end

  def atributos(caso, nunca)
    rubrica = [caso['esperado'], (@dados['nunca'] if nunca)].compact.join("\n\n")
    { titulo: "#{caso['codigo']} · #{caso['fala'].truncate(70)}", grupo: caso['grupo'], origem: 'caderno',
      ativo: caso.fetch('ativo', true), mensagens: [{ 'role' => 'user', 'content' => caso['fala'] }],
      criterios: (caso['criterios'] || {}).merge('rubrica' => rubrica) }
  end
end
