# Monitor de uptime do hub (item 27 do plano mestre)

O hub (chat.ramonantonio.adv.br) não tem monitoramento: se cair num sábado,
ninguém fica sabendo. A solução escolhida é **UptimeRobot no plano free**
(50 monitores, checagem a cada 5 min) — é configuração externa, sem código.

## O que o Eduardo precisa fazer (~5 minutos)

1. Criar conta em https://uptimerobot.com (free).
2. **Add New Monitor**:
   - Monitor type: `HTTP(s) — Keyword`
   - Friendly name: `ramon-hub`
   - URL: `https://chat.ramonantonio.adv.br/api`
   - Keyword: `version` (o endpoint `/api` responde JSON com a versão; se a
     palavra sumir da resposta, o hub está fora ou quebrado)
   - Keyword type: `exists` (alerta quando NÃO encontrar)
   - Monitoring interval: 5 minutes
3. **Alert contacts**: e-mail do Eduardo (padrão). Opcional: adicionar o
   webhook do ntfy.sh como contato (`https://ntfy.sh/<tópico do hub>`) pra
   tocar no celular — o mesmo tópico do push de lead novo.
4. Testar: pausar o monitor → Resume → conferir que o status fica "Up".

## Por que `/api` e não a home

`/api` é público, leve, não exige login e responde JSON do Rails — se ele
responde com `version`, o app (e o banco por trás do boot) está de pé. A home
redireciona pra tela de login do Vue e pode mascarar problemas de backend.

## Quando evoluir

- Sentry self-host (erros de aplicação) quando houver equipe — item 27, parte 2.
- Se o free tier apertar (retenção de logs), o plano pago é barato; reavaliar só com dor real.
