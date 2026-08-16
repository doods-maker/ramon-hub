# FORK-PONTO (ramon): seed idempotente da area Inteligencia — assistentes + skills
# (db/seeds/ramon/inteligencia/assistentes.yml) e FAQ aprovada (faq/*.md).
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
    Dir[DIR.join('faq', '*.md').to_s].sort.each { |arquivo| seed_faq(arquivo) }
    @contagem
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

  def seed_faq(arquivo)
    File.read(arquivo).sub(FRONT_MATTER, '').split(/^## /).drop(1).each do |bloco|
      pergunta, resposta = bloco.split("\n", 2)
      upsert_faq(pergunta.strip, resposta.to_s.strip)
    end
  end

  def upsert_faq(pergunta, resposta)
    faq = atendimento.responses.find_or_initialize_by(question: pergunta)
    return @contagem[:faq_puladas_editadas] += 1 if faq.persisted? && faq.edited?

    @contagem[faq.new_record? ? :faq_criadas : :faq_atualizadas] += 1
    faq.update!(answer: resposta, status: :approved, documentable: nil)
    # O before_validation marca edited=true em qualquer update; seed nao conta como edicao na UI.
    faq.update_column(:edited, false) if faq.edited? # rubocop:disable Rails/SkipsModelValidations
  end

  def atendimento
    @atendimento ||= @account.captain_assistants.find_by!(name: ATENDIMENTO)
  end
end
