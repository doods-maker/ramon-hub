require 'rails_helper'

# Registro de ações: o que cada ação sensível grava na trilha (tabela audits).
RSpec.describe 'Registro de ações — auditoria', type: :model do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }

  def trilha(registro, acao = nil)
    scope = Audited.audit_class.where(auditable_type: registro.class.name, auditable_id: registro.id).order(:id)
    acao ? scope.where(action: acao) : scope
  end

  describe 'lead' do
    let(:contact) { create(:contact, account: account) }
    let(:fechado) { create(:lead_stage, account: account, name: 'Fechado', is_won: true, position: 5) }
    let(:lead) { create(:lead, account: account, contact: contact) }

    it 'grava etapa, ganho e SDR com o antes e o depois', :aggregate_failures do
      etapa_antes = lead.lead_stage_id
      lead.update!(lead_stage: fechado, sdr: agente)

      audit = trilha(lead).last
      expect(audit.audited_changes['lead_stage_id']).to eq([etapa_antes, fechado.id])
      expect(audit.audited_changes['sdr_id']).to eq([nil, agente.id])
      expect(audit.audited_changes['won_at'].first).to be_nil
      expect(audit.audited_changes['won_at'].last).to be_present
      expect(audit.associated).to eq(account)
    end

    it 'não grava a criação (fica na lead_activities) nem o que não é sensível' do
      lead.update!(position: 9)

      expect(trilha(lead)).to be_empty
    end

    it 'grava a exclusão com o contato do lead', :aggregate_failures do
      lead.destroy!

      audit = trilha(lead, 'destroy').last
      expect(audit).to be_present
      expect(audit.audited_changes['contact_id']).to eq(contact.id)
    end
  end

  describe 'conversa' do
    let(:conversation) { create(:conversation, account: account) }

    after { Current.reset }

    it 'grava atribuição e transferência com quem fez (Current.user, como num job)', :aggregate_failures do
      Current.user = admin
      conversation.update!(assignee: agente)
      conversation.update!(assignee: admin)

      expect(trilha(conversation).map(&:audited_changes)).to eq([{ 'assignee_id' => [nil, agente.id] },
                                                                 { 'assignee_id' => [agente.id, admin.id] }])
      expect(trilha(conversation).last.user).to eq(admin)
    end

    it 'não grava o resto da conversa' do
      conversation.update!(priority: 'high')

      expect(trilha(conversation)).to be_empty
    end
  end

  describe 'dinheiro' do
    it 'grava a meta lançada e mudada', :aggregate_failures do
      meta = MetaComercial.create!(account: account, user: agente, papel: 'sdr', mes: Date.new(2026, 11, 1), meta: 20)
      meta.update!(meta: 25)

      expect(trilha(meta).pluck(:action)).to eq(%w[create update])
      expect(trilha(meta).last.audited_changes).to eq('meta' => [20, 25])
    end

    it 'grava o fechamento do extrato sem o payload' do
      extrato = ExtratoFechado.create!(account: account, user: agente, papel: 'sdr', competencia: Date.new(2026, 10, 1),
                                       fechado_em: Time.current, payload: { 'total' => 900 })

      expect(trilha(extrato).last.audited_changes.keys).to contain_exactly('user_id', 'papel', 'competencia')
    end
  end

  describe 'mesclagem de contatos' do
    it 'o contato que sai fica na trilha como mesclado no base' do
      base = create(:contact, account: account)
      mergee = create(:contact, account: account)

      ContactMergeAction.new(account: account, base_contact: base, mergee_contact: mergee).perform

      expect(trilha(mergee, 'destroy').last.comment).to eq("mesclado:#{base.id}")
    end
  end
end
