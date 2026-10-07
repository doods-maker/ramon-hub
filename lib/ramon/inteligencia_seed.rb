# FORK-PONTO (ramon): seed idempotente da area Inteligencia — assistentes + skills
# (db/seeds/ramon/inteligencia/assistentes.yml) e FAQ aprovada (faq/<tese>.md, tese = nome do arquivo).
# Chaves: assistente por name; skill por (assistant, title); FAQ por (assistant Atendimento, question).
class Ramon::InteligenciaSeed
  DIR = Rails.root.join('db/seeds/ramon/inteligencia')
  ATENDIMENTO = 'Atendimento (rascunho)'.freeze
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
    assistant = @account.captain_assistants.find_or_initialize_by(name: dados['name'])
    @contagem[assistant.new_record? ? :assistentes_criados : :assistentes_atualizados] += 1
    assistant.assign_attributes(
      description: dados['description'],
      config: (assistant.config || {}).merge(dados['config'] || {}),
      response_guidelines: dados['response_guidelines'],
      guardrails: dados['guardrails']
    )
    assistant.save!
    seed_skills(assistant, dados['skills'] || [])
  end

  def seed_skills(assistant, skills)
    skills.each do |skill|
      scenario = assistant.scenarios.find_or_initialize_by(title: skill['title'])
      @contagem[scenario.new_record? ? :skills_criadas : :skills_atualizadas] += 1
      scenario.update!(account: @account, description: skill['description'], instruction: skill['instruction'], enabled: true)
    end
    # Skill que saiu do yml: desabilita sem revalidar (a instrucao antiga pode citar tool que ja nao existe).
    # rubocop:disable Rails/SkipsModelValidations
    @contagem[:skills_desabilitadas] += assistant.scenarios.enabled.where.not(title: skills.pluck('title')).update_all(enabled: false)
    # rubocop:enable Rails/SkipsModelValidations
  end

  # [[tese, pergunta, resposta], ...] — tese = nome do arquivo (faq/<tese>.md).
  def faqs_do_seed
    Dir[DIR.join('faq', '*.md').to_s].sort.flat_map do |arquivo|
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
    # O before_validation marca edited=true em qualquer update; seed nao conta como edicao na UI.
    faq.update_column(:edited, false) if faq.edited? # rubocop:disable Rails/SkipsModelValidations
  end

  def atendimento
    @atendimento ||= @account.captain_assistants.find_by!(name: ATENDIMENTO)
  end
end
