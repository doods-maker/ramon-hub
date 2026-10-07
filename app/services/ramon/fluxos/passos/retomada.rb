# Passo da cadência de retomada (B4.3): conta a tentativa no lead — custom_attributes.follow_up, o mesmo contador do
# código (card, banner do painel, Watchdog e a regra dos 5 dias). Devolve o nº gravado em {tentativa} aos passos seguintes.
module Ramon::Fluxos::Passos::Retomada
  module_function

  def registrar_retomada(_config, ctx)
    lead = Ramon::Fluxos::Passos::Lead.exigir_lead(ctx)
    return { saida: 's', resumo: "faria: registrar a retomada nº #{Ramon::Fluxos::Retomada.tentativa(lead)}" } if ctx.ensaio?

    numero = Ramon::Fluxos::Retomada.registrar!(lead)
    { saida: 's', vars: { 'tentativa' => numero },
      resumo: "rascunho de retomada nº #{numero} pronto nas notas do lead — revise e envie pelo painel" }
  end
end
