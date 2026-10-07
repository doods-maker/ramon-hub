class Leads::HandoffNoteService
  DOSSIER_PREFIX = '📋 DOSSIÊ'.freeze
  MAX_BODY = 1000 # validação de LeadNote#body
  DUPLICATE_WINDOW = 5.minutes

  def initialize(lead:)
    @lead = lead
  end

  def perform
    return if recent_dossier?

    @lead.lead_notes.create!(account: @lead.account, user: nil, body: body)
  end

  # Público (B4.4): o passo "rotina" do fluxo pergunta antes, para o ensaio e a trilha.
  def recent_dossier?
    @lead.lead_notes
         .where('body LIKE ?', "#{DOSSIER_PREFIX}%")
         .exists?(created_at: DUPLICATE_WINDOW.ago..)
  end

  private

  # Texto único de passagem (Ramon::DossiePassagemTexto). LeadNote#body vale
  # até 1000 caracteres: passando disso, corta e fecha com o link da ficha, onde
  # está o texto completo (botão "Copiar dossiê").
  def body
    texto = "📋 #{Ramon::DossiePassagemTexto.new(lead: @lead).perform}"
    return texto if texto.length <= MAX_BODY

    ficha = "\n…\n\nTexto completo na ficha: #{Ramon::DossiePassagem.ficha_url(@lead)}"
    texto.first(MAX_BODY - ficha.length) + ficha
  end
end
