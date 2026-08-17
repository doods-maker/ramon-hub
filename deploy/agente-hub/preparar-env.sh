#!/usr/bin/env bash
# Prepara os segredos do agente do hub na VPS — roda como root, UMA vez, ANTES do install.sh.
# Não imprime segredo nenhum. Idempotente: não sobrescreve /opt/agente-hub/env se já existir
# nem duplica o bloco RAMON_AGENTE_* no chatwoot.env.
#   bash /opt/agente-hub/preparar-env.sh
set -euo pipefail

ENV_AGENTE=/opt/agente-hub/env
CHATWOOT_ENV=/opt/intranet-ramon/chatwoot.env
ENV_ANTIGO=/opt/agente/env            # residente do Buzz (token da assinatura já vive aqui)
EDUARDO_EMAIL=${EDUARDO_EMAIL:-adveduardoschlata@gmail.com}

if [ -f "$ENV_AGENTE" ]; then
  echo ">> $ENV_AGENTE já existe — não mexo."
else
  OA=$(sed -n 's/^export CLAUDE_CODE_OAUTH_TOKEN=//p; s/^CLAUDE_CODE_OAUTH_TOKEN=//p' "$ENV_ANTIGO" | head -1 | tr -d "\"'")
  MCP=$(sed -n 's/^RAMON_MCP_TOKEN=//p' "$CHATWOOT_ENV" | head -1)
  [ -n "$OA" ]  || { echo "!! token da assinatura não achado em $ENV_ANTIGO (rode: claude setup-token)"; exit 1; }
  [ -n "$MCP" ] || { echo "!! RAMON_MCP_TOKEN não achado em $CHATWOOT_ENV"; exit 1; }
  AG=$(openssl rand -hex 24)
  WS=$(openssl rand -hex 24)
  umask 077
  cat > "$ENV_AGENTE" <<EOF
CLAUDE_CODE_OAUTH_TOKEN=$OA
HUB_URL=https://chat.ramonantonio.adv.br
ACCOUNT_ID=2
HUB_AGENTE_TOKEN=$AG
HUB_MCP_TOKEN=$MCP
WEBHOOK_SECRET=$WS
EDUARDO_EMAIL=$EDUARDO_EMAIL
CAP_DIA=30
BIND=172.18.0.1
PORT=8765
SEDE_DIR=/opt/sede
CLAUDE_BIN=/home/agente/.local/bin/claude
MODELO=opus
ADVBOX_TAREFA_TIPO_ID=8745394
ADVBOX_TAREFA_RESPONSAVEL_ID=266778
EOF
  echo ">> $ENV_AGENTE criado (600)."
fi

# Lado do hub: mesmos segredos no chatwoot.env (RAMON_AGENTE_TOKEN = HUB_AGENTE_TOKEN; RAMON_AGENTE_SECRET = WEBHOOK_SECRET)
if grep -q '^RAMON_AGENTE_TOKEN=' "$CHATWOOT_ENV"; then
  echo ">> chatwoot.env já tem RAMON_AGENTE_* — não mexo."
else
  AG=$(sed -n 's/^HUB_AGENTE_TOKEN=//p' "$ENV_AGENTE")
  WS=$(sed -n 's/^WEBHOOK_SECRET=//p' "$ENV_AGENTE")
  cp "$CHATWOOT_ENV" "$CHATWOOT_ENV.bak-pre-agente-$(date +%Y%m%d)"
  cat >> "$CHATWOOT_ENV" <<EOF

# Agente do hub (Claude Code na VPS, usuário agente) — 17/08/2026
RAMON_AGENTE_TOKEN=$AG
RAMON_AGENTE_SECRET=$WS
RAMON_AGENTE_RUNNER_URL=http://172.18.0.1:8765/hub
RAMON_AGENTE_EDUARDO_EMAIL=$EDUARDO_EMAIL
EOF
  echo ">> bloco RAMON_AGENTE_* acrescentado ao chatwoot.env (backup feito). Reinicie chatwoot-web e chatwoot-worker depois do deploy."
fi
echo ">> pronto. Próximo: bash /opt/agente-hub/install.sh"
