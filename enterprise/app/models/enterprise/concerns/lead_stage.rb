# Etapa Documentos (spec §2): a etapa pode ter assistente próprio, que responde no lugar do da caixa
# (Captain::AssistenteDaConversa). Sem FK: assistente apagado = etapa volta a usar o da caixa.
module Enterprise::Concerns::LeadStage
  extend ActiveSupport::Concern

  included do
    belongs_to :captain_assistant, class_name: 'Captain::Assistant', optional: true
  end
end
