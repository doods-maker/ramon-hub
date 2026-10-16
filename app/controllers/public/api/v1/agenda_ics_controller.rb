# .ics público da reunião do hub ("salvar na minha agenda"). O token é o signed_id da tarefa (60 dias); inválido ou
# vencido = 404. Só o evento sai daqui (Ramon::Agenda::Convite), nada do cliente.
class Public::Api::V1::AgendaIcsController < PublicController
  def show
    task = LeadTask.find_signed(params[:token].to_s.delete_suffix('.ics'), purpose: :ics)
    return head :not_found unless task&.kind == 'meeting'

    render plain: Ramon::Agenda::Convite.new(task).ics, content_type: 'text/calendar'
  end
end
