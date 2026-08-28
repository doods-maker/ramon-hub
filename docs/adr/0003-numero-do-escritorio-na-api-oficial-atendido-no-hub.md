# Número do escritório na API oficial, atendido no hub por Setor

O WhatsApp do escritório (o número que a recepção atende) vivia no app WhatsApp
Business de um celular, com WhatsApp Web em 2–3 computadores; todo mundo via
todas as conversas e o repasse entre setores era na voz. Queríamos um menu de
entrada ("Recepção / Controladoria / Advogados") que filtrasse o atendimento.

Decidimos (2026-08-28) **levar o número do escritório para a Cloud API da Meta e
atendê-lo dentro do hub**, com uma **Portaria** (menu de botões nativo da API)
que encaminha cada conversa nova ao **Setor** escolhido — um Team do hub, com
fila própria e rodízio entre os online. A caixa do escritório fica separada das
caixas de tese (comercial), sem Lead automático e sem Assistente de IA; um lead
orgânico que cai na Recepção é encaminhado ao comercial por um botão. Quando a
Meta liberar mais números (teto de 2 sobe para 20 ao concluir a verificação),
cada tese ganha o seu — a Portaria segue só no número do escritório.

O que isso custa e por que aceitamos:

- **O número sai do celular e do WhatsApp Web.** A Meta não permite usar um
  número registrado na Cloud API no app comum; a "coexistência" app + API só é
  liberada via Embedded Signup de parceiro/Tech Provider, e o app RA CRM é de
  uso próprio (Direct Developer). Virar Tech Provider ou contratar parceiro
  para manter o WhatsApp Web foi rejeitado: custo e dependência para ganhar um
  cliente que, de qualquer forma, não tem fila por setor (todo dispositivo
  vinculado vê tudo).
- **A equipe migra para o hub num dia marcado.** Cada pessoa vê só a fila do
  seu Setor no navegador; o histórico antigo fica no celular como arquivo (a
  API não importa histórico).
- **Menu sem risco de banimento.** Botões interativos são recurso oficial da
  API e a resposta dentro da janela de 24h é gratuita; punição da Meta é por
  spam, template mal classificado ou denúncias — não por menu de entrada.

Alternativa "menu de saudação no próprio app WhatsApp Business" (sem API) foi
descartada porque não roteia: é só texto, e o objetivo era a fila por Setor.
