# Checklist completo em Documentos → Jurídico (Ramon::Documentos::Passagem). ADVBOX fora do ar: tenta de novo; a passagem é
# idempotente e o retry só tenta a tarefa ANÁLISE DO CASO, que não duplica.
class Ramon::Documentos::PassagemJob < ApplicationJob
  queue_as :default
  retry_on Ramon::AdvboxClient::UnavailableError, wait: :polynomially_longer, attempts: 3

  def perform(lead_id)
    lead = Lead.find_by(id: lead_id)
    Ramon::Documentos::Passagem.call(lead) if lead
  end
end
