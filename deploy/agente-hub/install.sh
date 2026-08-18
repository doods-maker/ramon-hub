#!/usr/bin/env bash
# Instala/atualiza o runner do agente do hub na VPS. Idempotente. Rodar como root:
#   bash /opt/agente-hub/install.sh   (depois de copiar deploy/agente-hub/* pra /opt/agente-hub)
set -euo pipefail

id agente >/dev/null 2>&1 || useradd --create-home --shell /bin/bash agente

chmod 750 /opt/agente-hub
install -d -o agente -g agente -m 750 /opt/agente-hub /opt/agente-hub/state /opt/agente-hub/work /opt/agente-hub/prompts
chown -R agente:agente /opt/agente-hub

[ -f /opt/agente-hub/env ] || { cp /opt/agente-hub/env.example /opt/agente-hub/env; echo ">> preencha /opt/agente-hub/env"; }
chmod 600 /opt/agente-hub/env; chown agente:agente /opt/agente-hub/env

# claude no home do agente (instalador oficial, não root)
sudo -u agente -H bash -c 'command -v ~/.local/bin/claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash'

# mcp.json com token expandido (exige env preenchido — preparar-env.sh — e envsubst do gettext-base)
command -v envsubst >/dev/null || { echo '!! envsubst ausente: apt-get install -y gettext-base'; exit 1; }
grep -q '^HUB_MCP_TOKEN=.' /opt/agente-hub/env || { echo '!! /opt/agente-hub/env sem HUB_MCP_TOKEN — rode preparar-env.sh antes'; exit 1; }
sudo -u agente -H bash -c 'set -a; . /opt/agente-hub/env; set +a; envsubst < /opt/agente-hub/mcp.json.example > /opt/agente-hub/mcp.json; chmod 600 /opt/agente-hub/mcp.json'

# sede legível pelo agente (sem escrita) — espelho sem credenciais por design
chmod -R o+rX /opt/sede

install -m 644 /opt/agente-hub/agente-hub.service /etc/systemd/system/agente-hub.service
systemctl daemon-reload
systemctl enable agente-hub
systemctl restart agente-hub   # restart (não --now): re-rodar o install atualiza o código em execução
systemctl --no-pager status agente-hub | head -5

echo ">> checando saude:"
curl -s http://172.18.0.1:8765/saude
