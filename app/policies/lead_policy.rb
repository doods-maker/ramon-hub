# Quem vê qual lead: admin e os times do comercial e do balcão veem o funil todo; os demais (ex.: advogados)
# veem o lead do cliente cuja conversa eles veem (mesma regra das conversas: caixa, atribuída ou time — ADR 0004),
# o cliente já ganho (passagem pro jurídico) e os casos da tela Cálculos (fora do funil). Lead sem conversa e
# ainda no funil: só a visão total.
class LeadPolicy < ApplicationPolicy
  EQUIPES_VISAO_TOTAL = [Ramon::Papeis::SDR, Ramon::Papeis::CLOSER, 'comercial', Chegada::RECEPCAO, 'controladoria'].freeze

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope if LeadPolicy.visao_total?(user, account, account_user)

      conversas = Conversations::PermissionFilterService.new(account.conversations, user, account).perform
      scope.where(conversation_id: conversas.select(:id))
           .or(scope.where(contact_id: conversas.select(:contact_id)))
           .or(scope.where.not(won_at: nil))
           .or(scope.where(source: Lead::FONTE_CALCULO))
    end
  end

  def self.visao_total?(user, account, account_user)
    account_user&.administrator? || user.teams.exists?(account_id: account.id, name: EQUIPES_VISAO_TOTAL)
  end

  def index?
    @account_user.administrator? || @account_user.agent?
  end

  # Por registro (record = Lead) o lead tem que estar no Scope; pela classe (lista, criar) não há registro.
  def show?
    index? && (!record.is_a?(Lead) || scope.exists?(id: record.id))
  end

  def for_conversation?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    show?
  end

  def portal_link?
    show?
  end

  def follow_up_draft?
    show?
  end

  def horarios_livres?
    show?
  end

  def encaminhar_comercial?
    @account_user.administrator? || @account_user.agent?
  end

  def destroy?
    @account_user.administrator?
  end

  # Reunião qualificada é base do prêmio do SDR (regulamento §2): quem marca é o
  # Closer do lead (ou alguém do time closer, se o lead ainda não tem) ou o gestor.
  def reuniao?
    return true if @account_user.administrator?
    return record.closer_id == @user.id if record.closer_id.present?

    Ramon::Papeis.membro?(@account, @user, Ramon::Papeis::CLOSER)
  end
end
