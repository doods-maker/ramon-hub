class Api::V1::Accounts::LeadConfigController < Api::V1::Accounts::BaseController
  before_action :current_account

  def show
    @stages = Current.account.lead_stages
    @benefit_types = Current.account.benefit_types
    @priorities = Current.account.lead_priorities
  end
end
