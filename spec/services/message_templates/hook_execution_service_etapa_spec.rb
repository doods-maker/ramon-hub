require 'rails_helper'

# Etapa Documentos (PR 2): o atendimento usa o assistente da etapa do lead (Captain::AssistenteDaConversa).
# Captain é enterprise e o CI roda sem enterprise/: estes exemplos rodam onde o Captain existe.
RSpec.describe MessageTemplates::HookExecutionService, if: ChatwootApp.enterprise? do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account, status: :pending) }
  let(:da_caixa) { create(:captain_assistant, account: account) }
  let(:da_etapa) { create(:captain_assistant, account: account, config: { 'handoff_message' => 'Chamei a equipe dos documentos.' }) }
  let(:etapa) { account.lead_stages.find_by!(label: 'fase-novo') }

  around { |example| with_modified_env(RAMON_ETAPA_DOCUMENTOS: 'on') { example.run } }

  before do
    create(:captain_inbox, captain_assistant: da_caixa, inbox: inbox)
    etapa.update!(captain_assistant: da_etapa)
    create(:lead, account: account, conversation: conversation, lead_stage: etapa)
  end

  it 'a resposta da IA vai com o assistente da etapa do lead' do
    expect { create(:message, conversation: conversation, message_type: :incoming, account: account) }
      .to have_enqueued_job(Captain::Conversation::ResponseBuilderJob).with(conversation, da_etapa, kind_of(Integer))
  end

  it 'cota estourada: o aviso de handoff usa o texto do assistente da etapa' do
    account.update!(limits: { 'captain_responses' => 100 },
                    custom_attributes: account.custom_attributes.merge('captain_responses_usage' => 100))

    expect { create(:message, conversation: conversation, message_type: :incoming, account: account) }
      .to have_enqueued_job(Conversations::ActivityMessageJob)
      .with(conversation, hash_including(content: 'Chamei a equipe dos documentos.'), kind_of(Integer))
  end
end
