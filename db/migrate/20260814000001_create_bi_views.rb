class CreateBiViews < ActiveRecord::Migration[7.1]
  def change
    create_view :bi_leads
    create_view :bi_stage_transitions
  end
end
