# Botão "Abrir no Drive" do Quadro do painel dos agentes: leva à peça (.docx) que a esteira gerou para o caso.
# Mesma porta do portão (ADR 0013): só quem vê o painel. O painel só manda o nome do arquivo (sem pasta, sem CPF);
# a busca fica dentro da raiz do Drive do hub, e só se redireciona para link do Google.
class Ramon::PainelAgentesPecaController < ApplicationController
  NOME = %r{\A[^/\\]{1,200}\.docx\z}
  DO_GOOGLE = /\A(docs|drive)\.google\.com\z/

  def show
    return render(plain: 'Entre no hub e tente de novo.', status: :unauthorized) unless sessao_do_painel?

    nome = params[:nome].to_s
    return head(:bad_request) unless nome.match?(NOME)

    link = Ramon::DriveClient.configured? ? Ramon::DriveClient.peca_na_raiz(nome) : nil
    return render(plain: 'Peça não encontrada no Drive do hub.', status: :not_found) unless do_google?(link)

    redirect_to link, allow_other_host: true
  rescue Google::Apis::Error
    render plain: 'O Drive não respondeu. Tente de novo em instantes.', status: :bad_gateway
  end

  private

  def sessao_do_painel? = Ramon::PainelAgentes.usuario_da_sessao(cookies[Ramon::PainelAgentes::COOKIE]).present?

  def do_google?(link)
    link.present? && URI.parse(link).host.to_s.match?(DO_GOOGLE)
  rescue URI::InvalidURIError
    false
  end
end
