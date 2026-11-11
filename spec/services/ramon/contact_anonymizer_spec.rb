require 'rails_helper'

describe Ramon::ContactAnonymizer do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, account: account, name: 'Joao da Silva', email: 'contato@exemplo.com',
                     phone_number: '+5548999998888', cpf: '52998224725',
                     custom_attributes: { 'apelido' => 'Joaozinho' })
  end
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:message) do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                     sender: contact, content: 'Sou o Joao, CPF 529.982.247-25, escreve pra contato@exemplo.com')
  end
  let!(:note) { create(:note, contact: contact, account: account, content: 'Cliente confirmou o CPF 529.982.247-25') }

  def perform
    described_class.new(contact).perform
  end

  it 'anonymizes the contact identity fields' do
    perform
    expect(contact.reload.name).to eq("Titular anonimizado ##{contact.id}")
    expect(contact.email).to be_nil
    expect(contact.phone_number).to be_nil
    expect(contact.cpf).to be_nil
    expect(contact.custom_attributes).to eq({})
  end

  it 'redacts PII from messages while preserving the conversation' do
    perform
    expect(message.reload.content).to include('[nome]')
    expect(message.content).to include('[cpf]')
    expect(message.content).not_to include('529.982.247-25')
    expect(message.content).not_to include('contato@exemplo.com')
    expect(conversation.reload).to be_present
  end

  it 'redacts PII from contact notes' do
    perform
    expect(note.reload.content).to include('[cpf]')
    expect(note.content).not_to include('529.982.247-25')
  end

  # Registro de ações: a trilha fica (somente-inclusão), só os valores de PII somem.
  it 'keeps the audit trail but redacts the old PII values', :aggregate_failures do
    contact.update!(phone_number: '+5548988887777', blocked: true)

    perform
    trilha = Audited.audit_class.where(auditable: contact).order(:id)
    edicao = trilha.find { |audit| audit.audited_changes.key?('blocked') && audit.action == 'update' }
    expect(edicao.audited_changes['phone_number']).to eq(%w[[anonimizado] [anonimizado]])
    expect(edicao.audited_changes['blocked']).to eq([false, true])
    expect(trilha.last.comment).to eq('anonimizado')
    expect(trilha.flat_map { |audit| audit.audited_changes.to_json }.join).not_to include('Joao', '52998224725', '8888')
  end

  it 'redacts the trail of a contact merged into this one' do
    duplicado = create(:contact, account: account, name: 'Joao Duplicado', phone_number: '+5548977776666')
    ContactMergeAction.new(account: account, base_contact: contact, mergee_contact: duplicado).perform

    perform
    destroy = Audited.audit_class.find_by(auditable_type: 'Contact', auditable_id: duplicado.id, action: 'destroy')
    expect(destroy.audited_changes.to_json).not_to include('Duplicado', '7777')
  end

  # Decisão de 11/11/2026: pedido de eliminação de cliente não apaga nada; fica registrado e a gestão decide.
  describe 'titular que é cliente' do
    let(:gestor) { create(:user, account: account, role: :administrator) }
    let(:won_stage) { account.lead_stages.find_by(is_won: true) }
    let(:open_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }

    before { gestor }

    def intacto
      expect(contact.reload).to have_attributes(name: 'Joao da Silva', email: 'contato@exemplo.com', cpf: '52998224725')
      expect(message.reload.content).to include('529.982.247-25')
      expect(note.reload.content).to include('529.982.247-25')
    end

    it 'cliente pelo contato: não apaga nada, registra no histórico do lead e avisa os gestores', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: won_stage, contact: contact, name: 'Lead ganho')

      expect { perform }.to raise_error(described_class::ClienteGanho)

      intacto
      expect(lead.lead_activities.where(kind: 'eliminacao_pedida').count).to eq(1)
      aviso = gestor.notifications.find_by(notification_type: 'ramon_fluxo_aviso')
      expect(aviso).to have_attributes(primary_actor: lead)
      expect(aviso.meta['label']).to include('Lead ganho')
    end

    it 'cliente só pela conversa (lead ganho sem contato ligado): não apaga nada', :aggregate_failures do
      create(:lead, account: account, lead_stage: won_stage, conversation: conversation)

      expect { perform }.to raise_error(described_class::ClienteGanho)
      intacto
    end

    it 'caso de cálculo sem contato, ligado pela conversa: não apaga nada', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: open_stage, conversation: conversation, source: Lead::FONTE_CALCULO)

      expect(lead).to have_attributes(contact_id: nil, won_at: nil)
      expect { perform }.to raise_error(described_class::ClienteGanho)
      intacto
    end

    # Sair da etapa de ganho zera won_at; o contrato que já existiu continua sendo caso de cliente.
    it 'contrato cancelado depois de apto (won_at zerado): não apaga nada', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: open_stage, contact: contact, apto_em: 1.month.ago, contrato_cancelado_em: 1.day.ago)

      expect(lead.won_at).to be_nil
      expect { perform }.to raise_error(described_class::ClienteGanho)
      intacto
    end

    it 'lead ganho e caso de cálculo mais novo: o pedido fica no histórico do lead do funil', :aggregate_failures do
      ganho = create(:lead, account: account, lead_stage: won_stage, contact: contact)
      create(:lead, account: account, lead_stage: open_stage, conversation: conversation, source: Lead::FONTE_CALCULO)

      expect { perform }.to raise_error(described_class::ClienteGanho)
      expect(ganho.lead_activities.where(kind: 'eliminacao_pedida').count).to eq(1)
    end

    it 'lead aberto (não ganho) não protege: o titular é anonimizado como antes', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: open_stage, contact: contact, conversation: conversation)

      perform

      expect(contact.reload.name).to eq("Titular anonimizado ##{contact.id}")
      expect(message.reload.content).not_to include('529.982.247-25')
      expect(lead.lead_activities.where(kind: 'eliminacao_pedida')).to be_empty
    end
  end

  it 'records the bulk deletion as made by who asked', :aggregate_failures do
    admin = create(:user, account: account, role: :administrator)
    Contacts::BulkActionService.new(account: account, user: admin, params: { action_name: 'delete', ids: [contact.id] }).perform

    audit = Audited.audit_class.where(auditable: contact).order(:id).last
    expect(audit.comment).to eq('anonimizado_em_massa')
    expect(audit.user).to eq(admin)
  end
end
