class Api::V1::Accounts::LeadConfigController < Api::V1::Accounts::BaseController
  before_action :current_account

  def show
    @stages = Current.account.lead_stages
    @benefit_types = Current.account.benefit_types
    @priorities = Current.account.lead_priorities
    # reorder(nil) anula o default_scope do Lead — DISTINCT + ORDER BY de coluna
    # fora do SELECT é erro no Postgres
    @sources = Current.account.leads.where.not(source: [nil, '']).reorder(nil).distinct.pluck(:source).sort
  end
end
