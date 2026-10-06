require 'rails_helper'

# Trigger audits_somente_inclusao (Registro de ações, LGPD): ninguém altera nem
# apaga a trilha; só a redação LGPD do anonimizador reescreve audited_changes.
RSpec.describe 'audits somente-inclusão', type: :model do
  let(:contact) { create(:contact, account: create(:account), phone_number: '+5548999998888') }
  # let!: criar fora do savepoint do `tentar` (senão o rollback leva o contato e o audit junto)
  let!(:audit) { Audited.audit_class.where(auditable: contact).last }

  # savepoint: o erro do Postgres não derruba a transação do teste
  def tentar(&)
    Audited.audit_class.transaction(requires_new: true, &)
  end

  # rubocop:disable Rails/SkipsModelValidations
  it 'bloqueia UPDATE e DELETE com erro claro', :aggregate_failures do
    expect { tentar { audit.update_columns(comment: 'mexido') } }.to raise_error(ActiveRecord::StatementInvalid, /somente-inclusão/)
    expect { tentar { audit.delete } }.to raise_error(ActiveRecord::StatementInvalid, /somente-inclusão/)
    expect { tentar { Audited.audit_class.where(id: audit.id).delete_all } }.to raise_error(ActiveRecord::StatementInvalid)
    expect(audit.reload.comment).to be_nil
  end

  it 'com a flag LGPD só deixa reescrever audited_changes', :aggregate_failures do
    tentar do
      Audited.audit_class.connection.execute("SELECT set_config('ramon.redacao_lgpd', 'on', true)")
      expect { tentar { audit.update_columns(username: 'outro') } }.to raise_error(ActiveRecord::StatementInvalid)
      audit.update_columns(audited_changes: { 'phone_number' => '[anonimizado]' })
      Audited.audit_class.connection.execute("SELECT set_config('ramon.redacao_lgpd', 'off', true)")
    end
    expect(audit.reload.audited_changes).to eq('phone_number' => '[anonimizado]')
  end
  # rubocop:enable Rails/SkipsModelValidations

  it 'continua aceitando INSERT' do
    expect { contact.update!(phone_number: '+5548911112222') }.to change { Audited.audit_class.where(auditable: contact).count }.by(1)
  end
end
