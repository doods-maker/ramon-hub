# FORK-PONTO (ramon): seed idempotente da area Inteligencia — assistentes + skills
# (db/seeds/ramon/inteligencia/assistentes.yml) e FAQ aprovada (faq/<tese>.md, tese = nome do arquivo).
# Chaves: assistente por name (ou antes:); skill por (assistant, seed_titulo|title), editada na tela fica; FAQ por (assistant Atendimento, question).
class Ramon::InteligenciaSeed
  DIR = Rails.root.join('db/seeds/ramon/inteligencia')
  ATENDIMENTO = 'Atendimento'.freeze
  FRONT_MATTER = /\A---\s*\n.*?\n---\s*\n/m

  def initialize(account)
    @account = account
    @contagem = Hash.new(0)
  end

  # @return [Hash] contagens (criados/atualizados/pulados) por tipo
  def run
    YAML.safe_load(DIR.join('assistentes.yml').read).fetch('assistentes').each { |dados| seed_assistente(dados) }
    faqs_do_seed.each { |tese, pergunta, resposta| upsert_faq(pergunta, resposta, tese) }
    @contagem
  end

  # So preenche a tese das FAQs do seed que ainda nao tem (rake ramon:inteligencia:teses).
  # Nao toca em resposta, status nem nas skills — pode rodar em producao sem medo.
  # @return [Integer] quantas FAQs ganharam tese
  def preencher_teses
    faqs_do_seed.sum do |tese, pergunta, _resposta|
      atendimento.responses.where(question: pergunta, tese: nil).update_all(tese: tese) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  def seed_assistente(dados)
    assistant = achar_assistente(dados)
    @contagem[assistant.new_record? ? :assistentes_criados : :assistentes_atualizados] += 1
    assistant.assign_attributes(
      name: dados['name'],
      description: dados['description'],
      # ramon_modo_rascunho: marca morta (ninguém lia; o modo é por conversa — I-AS4)
      config: (assistant.config || {}).except('ramon_modo_rascunho').merge(dados['config'] || {}),
      response_guidelines: dados['response_guidelines'],
      guardrails: dados['guardrails']
    )
    assistant.save!
    seed_skills(assistant, dados['skills'] || [])
  end

  # Renomear no yml não cria outro assistente: acha pelo nome de hoje ou por um dos antigos (campo antes:).
  def achar_assistente(dados)
    @account.captain_assistants.find_by(name: [dados['name'], *dados['antes']]) ||
      @account.captain_assistants.new(name: dados['name'])
  end

  def seed_skills(assistant, skills)
    skills.each { |skill| seed_skill(assistant, skill) }
    # Skill que saiu do yml: desabilita sem revalidar (a instrucao antiga pode citar tool que ja nao existe).
    # Editada ou criada na tela fica como esta (I-SK5).
    # rubocop:disable Rails/SkipsModelValidations
    @contagem[:skills_desabilitadas] += assistant.scenarios.enabled.where(edited: false)
                                                 .where.not(title: skills.pluck('title')).update_all(enabled: false)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Acha pela origem no yml (sobrevive a renomear na tela) e, nas antigas, pelo título.
  def seed_skill(assistant, skill)
    scenario = assistant.scenarios.find_by(seed_titulo: skill['title']) ||
               assistant.scenarios.find_or_initialize_by(title: skill['title'])
    return completar_editada(scenario, skill) if scenario.edited?

    @contagem[scenario.new_record? ? :skills_criadas : :skills_atualizadas] += 1
    scenario.update!(account: @account, description: skill['description'], instruction: skill['instruction'],
                     enabled: true, seed_titulo: skill['title'], exemplo: skill['exemplo'], papeis: skill['papeis'] || [])
  end

  # Editada na tela (I-SK5): o seed não mexe — só preenche fala de exemplo e papéis ainda vazios (A5).
  def completar_editada(scenario, skill)
    scenario.update_columns(exemplo: scenario.exemplo.presence || skill['exemplo'], # rubocop:disable Rails/SkipsModelValidations
                            papeis: scenario.papeis.presence || skill['papeis'] || [])
    @contagem[:skills_puladas_editadas] += 1
  end

  # [[tese, pergunta, resposta], ...] — tese = nome do arquivo (faq/<tese>.md).
  def faqs_do_seed
    Dir[DIR.join('faq', '*.md').to_s].flat_map do |arquivo|
      tese = File.basename(arquivo, '.md')
      File.read(arquivo).sub(FRONT_MATTER, '').split(/^## /).drop(1).map do |bloco|
        pergunta, resposta = bloco.split("\n", 2)
        [tese, pergunta.strip, resposta.to_s.strip]
      end
    end
  end

  # Tese: so preenche se vazia (a escolhida na tela vale, editada ou nao).
  def upsert_faq(pergunta, resposta, tese)
    faq = atendimento.responses.find_or_initialize_by(question: pergunta)
    if faq.persisted? && faq.edited?
      faq.update_column(:tese, tese) if faq.tese.nil? # rubocop:disable Rails/SkipsModelValidations
      return @contagem[:faq_puladas_editadas] += 1
    end

    @contagem[faq.new_record? ? :faq_criadas : :faq_atualizadas] += 1
    faq.update!(answer: resposta, status: :approved, documentable: nil, tese: faq.tese || tese)
    # mark_as_edited marca edited=true quando pergunta ou resposta mudam (aqui a resposta muda); seed nao conta como edicao na UI.
    faq.update_column(:edited, false) if faq.edited? # rubocop:disable Rails/SkipsModelValidations
  end

  def atendimento
    @atendimento ||= @account.captain_assistants.find_by!(name: ATENDIMENTO)
  end
end
