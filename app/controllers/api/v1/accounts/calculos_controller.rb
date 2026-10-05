# Histórico da tela Cálculos: lista o que já foi calculado (cliente, tipo,
# data/hora, quem calculou e o valor principal), reabre um cálculo no estado
# exato, vincula um cálculo a um cliente e apaga registro indevido.
class Api::V1::Accounts::CalculosController < Api::V1::Accounts::BaseController
  LIMIT = 50

  before_action :current_account
  before_action :fetch_calculo, only: [:destroy, :reabrir, :vincular]
  before_action :check_authorization

  def index
    calculos = Current.account.calculos.recentes.includes(:user, :lead).limit(LIMIT)
    calculos = calculos.do_cliente(params[:q].to_s.strip) if params[:q].present?
    render json: { payload: calculos.map { |calculo| linha(calculo) } }
  end

  def destroy
    @calculo.destroy!
    head :no_content
  end

  # Devolve o CNIS do cálculo a um caso — é o servidor que lê `lead.cnis` na
  # hora de recalcular, então restaurar só no browser não bastaria. Cálculo
  # rápido volta SEMPRE no rascunho de quem está abrindo (o rascunho de origem
  # pode ser de outra pessoa). De lead real, destino=rascunho copia pro meu
  # rascunho e deixa o lead intacto; sem destino, restaura no próprio lead (a
  # tela pergunta antes quando isso troca um CNIS diferente).
  def reabrir
    destino = abrir_no_rascunho? ? rascunho_com_tese : @calculo.lead
    destino.update!(cnis: @calculo.cnis_snapshot) if @calculo.cnis_snapshot.present?
    render json: reaberto(destino)
  end

  # Vincula o cálculo a um cliente: o CNIS do cálculo vai pro lead escolhido e
  # a tela abre o cálculo dele. Lead que já tem outro CNIS só é sobrescrito com
  # substituir=true (a tela pergunta antes). Cálculo rápido passa a ser do cliente.
  def vincular
    alvo = Current.account.leads.find(params[:lead_id])
    authorize(alvo, :update?)
    return render json: { error: 'LEAD_TEM_CNIS' }, status: :conflict if conflito?(alvo)

    alvo.update!(cnis: @calculo.cnis_snapshot) if @calculo.cnis_snapshot.present?
    adotar_rascunho(alvo) if @calculo.lead.rascunho_de_calculo?
    render json: reaberto(alvo)
  end

  private

  def fetch_calculo
    @calculo = Current.account.calculos.find(params[:id])
  end

  # Apagar depende de quem calculou: a policy precisa do registro, não da classe.
  def check_authorization
    authorize(@calculo || Calculo)
  end

  def abrir_no_rascunho?
    @calculo.lead.rascunho_de_calculo? || params[:destino] == 'rascunho'
  end

  # A tese vai junto quando o cálculo é de um caso de verdade: o Honorário do
  # rascunho sai pela mesma regra do lead de origem.
  def rascunho_com_tese
    rascunho = Lead.rascunho_de!(Current.account, Current.user)
    rascunho.update!(thesis_id: @calculo.lead.thesis_id) unless @calculo.lead.rascunho_de_calculo?
    rascunho
  end

  # Cálculo rápido vinculado sai do rascunho e passa a constar no cliente.
  def adotar_rascunho(alvo)
    @calculo.update!(lead: alvo, segurado_nome: @calculo.segurado_nome.presence || alvo.contact&.name)
  end

  def conflito?(alvo)
    !ActiveModel::Type::Boolean.new.cast(params[:substituir]) && cnis_diferente?(alvo, @calculo)
  end

  def cnis_diferente?(lead, calculo)
    calculo.cnis_snapshot.present? && lead.cnis.present? && lead.cnis != calculo.cnis_snapshot
  end

  def reaberto(lead)
    {
      lead_id: lead.id,
      tipo: @calculo.tipo,
      params: @calculo.snapshot['params'] || {},
      cnis: lead.cnis_detalhe,
      thesis_id: lead.thesis_id,
      thesis_name: lead.thesis&.name
    }
  end

  def linha(calculo)
    dados(calculo).merge(
      # sem CNIS no snapshot, reabrir só devolve os campos digitados
      tem_cnis: calculo.cnis_snapshot.present?,
      valor: calculo.snapshot['valor'],
      rascunho: calculo.lead.rascunho_de_calculo?,
      # reabrir no lead trocaria o CNIS diferente que ele tem hoje → a tela pergunta
      substitui_cnis: !calculo.lead.rascunho_de_calculo? && cnis_diferente?(calculo.lead, calculo),
      pode_apagar: CalculoPolicy.new(pundit_user, calculo).destroy?
    )
  end

  def dados(calculo)
    {
      id: calculo.id,
      tipo: calculo.tipo,
      lead_id: calculo.lead_id,
      segurado_nome: calculo.segurado_nome,
      segurado_cpf: calculo.segurado_cpf,
      der: calculo.der,
      created_at: calculo.created_at.iso8601,
      user_name: calculo.user&.name
    }
  end
end
