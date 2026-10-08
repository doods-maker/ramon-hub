# FORK-PONTO (ramon, A5 — I-X7): "Memória do contato". Ao resolver a conversa (CaptainListener, chave feature_memory),
# anota no LEAD (painel → Notas) o que a IA aprendeu. Prompt, texto mascarado e o que pode ser gravado:
# Ramon::MemoriaContato (FOSS, testado no CI). Sem lead, sem memória. Para no dia em que o gasto chega ao teto.
# Modelo = o das "FAQs geradas" (Uso e custo); custo em linha própria (função memoria_contato).
class Captain::Llm::ContactNotesService < Llm::BaseAiService
  include Integrations::LlmInstrumentation

  def initialize(assistant, conversation)
    super()
    @assistant = assistant
    @conversation = conversation
    @lead = conversation.account.leads.find_by(conversation_id: conversation.id)
    @model = Ramon::LlmEscolha.para(conversation.account, 'documentos')[:model]
  end

  def generate_and_update_notes
    return if @lead.nil? || Ramon::IaGastoAlerta.passou_do_teto?(@conversation.account)

    Ramon::MemoriaContato.gravar!(@lead, @conversation.display_id, generate_notes)
  end

  private

  def generate_notes
    @content = Ramon::MemoriaContato.texto(@conversation, @lead)
    response = instrument_llm_call(instrumentation_params) do
      chat.with_params(response_format: { type: 'json_object' }).with_instructions(Ramon::MemoriaContato::PROMPT).ask(@content)
    end
    Ramon::MemoriaContato.itens(response.content)
  rescue RubyLLM::Error => e
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    []
  end

  def instrumentation_params
    {
      span_name: 'llm.captain.contact_notes', model: @model, temperature: @temperature,
      account_id: @conversation.account_id, conversation_id: @conversation.display_id, feature_name: 'contact_notes',
      messages: [{ role: 'system', content: Ramon::MemoriaContato::PROMPT }, { role: 'user', content: @content }],
      metadata: { assistant_id: @assistant.id }
    }
  end
end
