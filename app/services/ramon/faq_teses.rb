# FAQ por tese (I-FQ1, revisto 20/10/2026): a FAQ aponta para as teses reais da conta (captain_assistant_responses.
# thesis_ids, uma ou várias — ex.: as FAQs trabalhistas valem para as 4 teses "Trabalhista — …") ou é Geral (vale para
# todo caso). Nenhuma das duas = sem tese. Fica em app/ (não em enterprise/) para o CI cobrir: recebe o scope pronto.
module Ramon::FaqTeses
  GERAL = 'geral'.freeze
  SEM = 'sem'.freeze

  # Slug do seed (db/seeds/ramon/inteligencia/faq/<slug>.md) → nome das teses (ILIKE). "_" no lugar da letra acentuada:
  # casa com ou sem acento. Mesma regra copiada na migração 20261020130000 (migração não lê código do app).
  SLUGS = {
    'auxilio-acidente' => 'Aux_lio-acidente%',
    'auxilio-doenca' => 'Aux_lio por incapacidade tempor_ria%',
    'aposentadoria-invalidez' => 'Aposentadoria por incapacidade permanente%',
    'bpc-loas' => 'BPC%',
    'acrescimo-25' => 'Acr_scimo de 25%',
    'trabalhista' => 'Trabalhista%',
    'isencao-ir' => 'Isen__o de IR%',
    'salario-maternidade' => 'Sal_rio-maternidade%'
  }.freeze

  module_function

  # { geral:, thesis_ids: } do slug nas teses da conta. Slug desconhecido (ou conta ainda sem as teses) = sem tese.
  def do_slug(account, slug)
    return { geral: true, thesis_ids: [] } if slug == GERAL

    padrao = SLUGS[slug]
    { geral: false, thesis_ids: padrao ? account.theses.where('name ILIKE ?', padrao).pluck(:id) : [] }
  end

  def sem_tese?(faq) = !faq.geral && faq.thesis_ids.blank?

  # O que a IA (faq_lookup e "Testar pergunta") pode achar para um lead desta tese: as FAQs da tese, as Gerais e as
  # ainda sem tese (sem classificar não some do atendimento). Lead sem tese = todas, como antes.
  def para_tese(scope, thesis_id)
    return scope if thesis_id.blank?

    scope.where("geral OR thesis_ids = '{}' OR ? = ANY(thesis_ids)", thesis_id.to_i)
  end

  # Filtro da tela de FAQs: 'geral' | 'sem' | id da tese (só as ligadas a ela). Outro valor (ex.: slug antigo na URL) = todas.
  def filtrar(scope, valor)
    case valor.to_s
    when GERAL then scope.where(geral: true)
    when SEM then scope.where(geral: false).where("thesis_ids = '{}'")
    else
      id = Integer(valor.to_s, exception: false)
      id ? scope.where('? = ANY(thesis_ids)', id) : scope
    end
  end

  # Tese do lead do turno: no Testar com roteiro, a do lead descartável; no atendimento/copiloto, a do lead da conversa.
  def tese_do_turno(account_id, state)
    teste = state&.dig(:roteiro_teste)
    return teste['thesis_id'] if teste

    conversa = state&.dig(:conversation, :id)
    Lead.where(account_id: account_id, conversation_id: conversa).pick(:thesis_id) if conversa
  end
end
