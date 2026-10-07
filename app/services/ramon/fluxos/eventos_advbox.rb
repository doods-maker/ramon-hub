# B4.5 (spec §8): o que o hub faz quando o ADVBOX avisa uma etapa/tarefa (Flowter → Ramon::AdvboxEventProcessor) — pelo
# código (Ramon::AdvboxEventRegras, como sempre) ou pelo fluxo "Eventos do ADVBOX", conforme a chave
# (RAMON_FLUXO_EVENTOS_ADVBOX + o fluxo em modo normal). A decisão é do evento: lida UMA vez aqui.
# 1) o fluxo migrado, na hora (Disparo::NA_HORA), com 'assumido' — age, ou ensaia antes do código;
# 2) o código, se o fluxo não está no comando OU não pegou o evento (o mesmo lead ainda numa execução viva, motor com
#    erro, fluxo desligado no meio, filtro de regras editado no gatilho) — nada se perde, nada em dobro;
# 3) os fluxos comuns de evento do ADVBOX, sem 'assumido', como sempre.
# Contrato fechado só move o lead para o ganho; dossiê/ADVBOX/NPS são do Lead ganho, que decide sozinho (LeadGanho).
module Ramon::Fluxos::EventosAdvbox
  module_function

  def processar(lead, regra, nome)
    dados = { 'regra' => regra, 'texto' => nome, 'primeiro_nome' => primeiro_nome(lead), 'hoje' => Time.zone.today.strftime('%d/%m/%Y') }
    assumido = Ramon::Fluxos::Migracao.assumiu?(lead.account, 'eventos_advbox')
    feitas = Ramon::Fluxos::Disparo.externo('evento_advbox', lead, dados.merge('assumido' => assumido))
    Ramon::AdvboxEventRegras.new(lead.account).public_send(regra, lead, nome) unless assumido && feitas.any?
    Ramon::Fluxos::Disparo.externo('evento_advbox', lead, dados)
  end

  # Como o código escreve nos rascunhos (Ramon::AdvboxEventRegras#first_name) — vai pronto no gatilho como {primeiro_nome}.
  def primeiro_nome(lead) = lead.name.to_s.split.first.presence || 'cliente'
end
