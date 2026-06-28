require 'rails_helper'

RSpec.describe 'create_ramon_leads migration schema' do
  it 'cria as 4 tabelas com as colunas-chave' do
    conn = ActiveRecord::Base.connection
    expect(conn.table_exists?(:lead_stages)).to be true
    expect(conn.table_exists?(:benefit_types)).to be true
    expect(conn.table_exists?(:lead_priorities)).to be true
    expect(conn.table_exists?(:leads)).to be true

    lead_columns = conn.columns(:leads).map(&:name)
    expect(lead_columns).to include('account_id', 'lead_stage_id', 'position', 'custom_attributes')

    stage_columns = conn.columns(:lead_stages).map(&:name)
    expect(stage_columns).to include('is_won', 'is_lost', 'position')
  end
end
