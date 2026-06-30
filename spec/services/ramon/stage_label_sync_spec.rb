# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ramon::StageLabelSync do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:novo) { account.lead_stages.find_by(label: 'fase-novo') }
  let(:qualif) { account.lead_stages.find_by(label: 'fase-qualificacao') }

  describe '.apply_to_conversation' do
    it 'aplica a fase-* da etapa na conversa' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      described_class.apply_to_conversation(lead)
      expect(conversation.reload.label_list).to contain_exactly('fase-novo')
    end

    it 'cria a Label fase-* sob demanda (cor canônica + show_on_sidebar) ao aplicar' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      expect { described_class.apply_to_conversation(lead) }
        .to change { account.labels.where(title: 'fase-novo').count }.from(0).to(1)
      label = account.labels.find_by(title: 'fase-novo')
      expect(label.show_on_sidebar).to be(true)
      expect(label.color).to eq('#6b7280')
    end

    it 'troca a fase-* antiga pela nova, preservando labels não-fase' do
      conversation.update_labels(%w[urgente fase-novo])
      lead = create(:lead, account: account, lead_stage: qualif, conversation: conversation)
      described_class.apply_to_conversation(lead)
      expect(conversation.reload.label_list).to contain_exactly('urgente', 'fase-qualificacao')
    end

    it 'é no-op quando já está igual (guarda de igualdade)' do
      conversation.update_labels(%w[fase-novo])
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      expect { described_class.apply_to_conversation(lead) }
        .not_to(change { conversation.reload.label_list.sort })
    end

    it 'é no-op quando o lead não tem conversa' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: nil)
      expect { described_class.apply_to_conversation(lead) }.not_to raise_error
    end
  end

  describe '.apply_to_lead' do
    it 'move o lead pra etapa da fase-* adicionada' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      described_class.apply_to_lead(conversation, ['fase-qualificacao'])
      expect(lead.reload.lead_stage).to eq(qualif)
    end

    it 'self-heal: remove outras fase-* deixando só a adicionada' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      conversation.update_labels(%w[fase-novo fase-qualificacao])
      described_class.apply_to_lead(conversation, ['fase-qualificacao'])
      expect(conversation.reload.label_list).to contain_exactly('fase-qualificacao')
      expect(lead.reload.lead_stage).to eq(qualif)
    end

    it 'ignora quando nenhuma fase-* foi adicionada' do
      lead = create(:lead, account: account, lead_stage: novo, conversation: conversation)
      expect { described_class.apply_to_lead(conversation, ['urgente']) }
        .not_to(change { lead.reload.lead_stage_id })
    end

    it 'no-op quando a conversa não tem lead' do
      expect { described_class.apply_to_lead(conversation, ['fase-novo']) }.not_to raise_error
    end

    it 'é no-op quando o lead já está na etapa (guarda de igualdade)' do
      lead = create(:lead, account: account, lead_stage: qualif, conversation: conversation)
      conversation.update_labels(%w[fase-qualificacao])
      expect { described_class.apply_to_lead(conversation, ['fase-qualificacao']) }
        .not_to(change { lead.reload.updated_at })
    end
  end
end
