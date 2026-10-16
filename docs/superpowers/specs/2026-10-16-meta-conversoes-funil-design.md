# Rastreamento Meta no funil (API de Conversões + gasto por anúncio) — desenho

Data: 16/10/2026 · Pedido do Eduardo · Status: rascunho para aprovação

## Por quê

Os anúncios da banca levam **direto para o WhatsApp** (click-to-WhatsApp). Hoje a Meta só sabe que alguém mandou mensagem,
e nada sobre quem virou reunião ou contrato. Por isso ela otimiza para quem conversa, inclusive o curioso que manda "oi" e
some. O hub já guarda a digital do clique (`ctwa_clid`) e o anúncio de origem (`source_id`) em
`lead.custom_attributes['meta_referral']` (`Ramon::LeadDaConversa.apply_meta_referral`). Ele só não devolve nada para a Meta.

Sucesso, na ordem do Eduardo:
1. **Custo por reunião agendada, por anúncio**, e a Meta trazendo mais gente que agenda.
2. **Quais anúncios viram contrato**, com o custo por contrato visto no hub/Metabase, mesmo quando a Meta não credita.
3. Como efeito: pagar menos por curioso.

## O que é

Duas peças:

**A. Avisos de conversão (hub → Meta).** Quando um lead que veio de anúncio de WhatsApp (tem `ctwa_clid`) avança no funil,
o hub manda um evento para a API de Conversões para Mensagens Comerciais
(`POST /{dataset_id}/events`, `action_source: business_messaging`, `messaging_channel: whatsapp`,
`user_data: { whatsapp_business_account_id, ctwa_clid }`).

| Momento no hub | Gatilho | Evento Meta | Observação |
|---|---|---|---|
| Lead qualificado | entrou na etapa de label `fase-qualificacao` | `LeadSubmitted` | |
| Reunião agendada | entrou na etapa `fase-reuniao-agendada` | `QualifiedLead` | **alvo de otimização das campanhas** |
| Reunião realizada | entrou na etapa `fase-reuniao-realizada` | `InitiateCheckout` | |
| Contrato assinado | `won_at` preenchido | `Purchase` com `value` = valor do lead, `currency` = BRL | |

Os 4 momentos foram escolhidos pelo Eduardo. A **tradução para os nomes da Meta foi decisão minha**: a Meta não tem
"reunião" na lista de mensagens comerciais, que é Purchase, LeadSubmitted, InitiateCheckout, AddToCart, ViewContent,
QualifiedLead, Order*, CartAbandoned, RatingProvided e ReviewProvided.

**B. Gasto por anúncio (Meta → hub).** Uma rotina diária lê, pela Marketing API (insights por `ad_id`, por dia), o gasto,
as impressões e os cliques da conta de anúncios e grava numa tabela do hub. No Metabase, o painel "Análise Comercial" (id 3)
ganha cartões por anúncio e campanha: gasto, leads, reuniões agendadas, contratos, custo por reunião e custo por contrato.
O cruzamento é pelo `source_id` do `meta_referral`, que é o id do anúncio quando `source_type = 'ad'`.

## Regras

- **Uma vez por lead e por evento.** Se o card for e voltar no kanban, nada é reenviado. Use um `event_id` estável
  (`lead-<id>-<evento>`) e um carimbo no lead.
- **Só para a frente:** entrar direto numa etapa adiante não dispara os eventos das etapas puladas. *(decisão minha;
  o builder pode mudar se a Meta recomendar enviar a sequência)*
- **Só leads com `ctwa_clid`.** Lead de indicação, de LP ou do Instagram não gera evento.
- **Nada sensível sai:** nem nome, telefone, CPF, tese, doença ou texto da conversa. Só os ids acima e o valor do contrato.
  O telefone não vai nem com hash. *(decisão minha: LGPD e OAB)*
- **Janela de 7 dias:** a Meta só credita ao anúncio o que acontece até 7 dias depois do clique. Envie mesmo depois disso,
  porque não atrapalha. Mas o "custo por contrato" de verdade vem da peça B, não do Gerenciador.
- **Desligado por padrão.** Uma chave liga e desliga (env no padrão `RAMON_*`, ou interruptor na tela, a critério do builder).
  Liga quando o **número oficial da banca** entrar no hub. Hoje só existe "WhatsApp Cloud (teste)"; a migração depende do
  Tech Provider, ver `comercial\docs\2026-09-21-roteiro-app-review-tech-provider.md`.
- **Falha não trava o funil:** job com retry; erro fica registrado e visível, e o lead anda igual.
- **Rastro:** cada envio (ok ou erro) fica registrado e consultável, para conferência e para o Metabase.

## Fora do escopo

- Pixel das LPs. O código já existe em `landing-pages` (liga com `PUBLIC_META_PIXEL_ID`), mas os anúncios não usam LP agora.
- Instagram DM e Messenger. Mesma API, mas `ctwa_clid` é do WhatsApp; fica para depois.
- Mudar campanhas no Gerenciador: a troca do alvo para `QualifiedLead` é ação do Eduardo, com o passo a passo da entrega.
- Evento de "perdido".

## Restrições e riscos conhecidos

- **Permissões:** a API de Conversões para mensagens pede `whatsapp_business_management` e
  `whatsapp_business_manage_events`. A peça B pede `ads_read`. A Meta fala em "Advanced access", e o app RA CRM está em
  modo dev ([[meta-app-ra-crm]]). **Primeiro passo do builder:** provar com 1 evento de teste ("Eventos de teste" do
  Gerenciador) que o token do próprio negócio (System User do BM da banca, dono do app e do WABA) basta, sem App Review.
  Se não bastar, parar e avisar o Eduardo antes de construir o resto.
- **Token:** a Meta recomenda reusar o token do canal WhatsApp (`provider_config['api_key']` do `Channel::Whatsapp`). O
  `whatsapp_business_account_id` sai do mesmo lugar (`provider_config['business_account_id']`). O `dataset_id` vem de
  `GET/POST /{WABA_ID}/dataset`, que cria ou devolve o existente.
- **Conta de anúncios** (`act_…`) para a peça B: o Eduardo informa.
- A conta (`Account`) é uma só (fork single-tenant), mas siga o padrão do hub de ler o canal pela conversa do lead.

## Entrega e gates do Eduardo

1. Passo a passo (doc em `comercial\docs\`) para: conferir ou criar o conjunto de dados ligado ao WABA no Gerenciador de
   Eventos, gerar ou confirmar o token com as permissões, informar a conta de anúncios e, depois, trocar o objetivo das
   campanhas para `QualifiedLead`.
2. Prova na caixa de teste: lead de teste com `ctwa_clid` de teste → eventos aparecendo em "Eventos de teste".
3. Smoke em bloco por seção (regra do Eduardo), no padrão dos docs de entrega.
4. Ligar a chave = ação do Eduardo, quando o número oficial estiver no hub.

**Peça B também espera o número oficial** (Eduardo, 16/10): hoje os anúncios caem num número fora do hub, então não
haveria lead para cruzar. As duas peças ligam juntas.

**Ordem:** este projeto vem **depois** do funil automático (`2026-10-16-funil-automatico-design.md`), decisão do Eduardo.

## Decisões da revisão do builder (16/10, minhas — conferir)

- **Passo 0 também confere o alvo:** confirmar na documentação da Meta que `QualifiedLead` pode ser escolhido como
  otimização numa campanha click-to-WhatsApp. Se não puder, parar e levar ao Eduardo um mapeamento novo, por exemplo
  reunião agendada → `LeadSubmitted`.
- **WABA e caixa gravados no clique:** junto do `meta_referral`, gravar o id da caixa e do WABA de onde o clique veio.
  O envio usa esses ids, e não a conversa atual do lead, que pode ter mudado para outra caixa.
- **Valor do `Purchase`:** o `value` atual do lead, mesmo quando é estimado. Se for nulo (tese fora da JUR-02), o campo
  vai sem valor.
- **Último clique vence:** um segundo clique em outro anúncio sobrescreve o `meta_referral`, e a atribuição fica com o
  último anúncio.
- **Só para a frente** = o carimbo por evento. Não precisa comparar `position`. Reunião pelo Cal.com cai no mesmo gatilho.
- **Metabase:** cartões novos saem de uma `bi_leads` v02 que expõe `source_id`, mais uma view `bi_*` do gasto, no padrão
  de `scripts/metabase_bi_rewrite.py`.

## Fica com o builder

Forma do gatilho (callback do Lead, ouvinte ou fluxo de sistema em Automações), nome e formato das tabelas, onde mostrar
erro/status na tela, horário da rotina de gasto, versão da Graph API e desenho dos cartões do Metabase, seguindo os
cartões existentes.
