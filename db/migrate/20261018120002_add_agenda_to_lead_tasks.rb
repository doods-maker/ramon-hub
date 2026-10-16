# Agenda no hub: dono da agenda (Closer) da reunião, id do evento no Google, link do Meet e formato (video | whatsapp).
class AddAgendaToLeadTasks < ActiveRecord::Migration[7.1]
  def change
    add_reference :lead_tasks, :agenda_user, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
    add_column :lead_tasks, :google_event_id, :string
    add_column :lead_tasks, :meet_url, :string
    add_column :lead_tasks, :formato, :string, default: 'video', null: false
  end
end
