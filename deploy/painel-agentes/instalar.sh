#!/usr/bin/env bash
# Liga o painel dos agentes na VPS (ADR 0013). Rode como root, com o hub já na versão que tem o portão:
#   bash instalar.sh <e-mail do login no hub>            liga (pode repetir, não duplica nada)
#   bash instalar.sh --desfazer                          volta ao estado anterior
set -euo pipefail

BASE=/opt/intranet-ramon
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL=https://chat.ramonantonio.adv.br:8443/
SITE=chat.ramonantonio.adv.br:8443
cd "$BASE"

web_sobe() {
  docker compose up -d chatwoot-web
}

if [ "${1:-}" = "--desfazer" ]; then
  B=$(ls -d "$BASE"/.painel-agentes-bak-* | sort | head -1)
  # cat > mantém o inode: o Caddyfile é montado como arquivo no container.
  cat "$B/Caddyfile" > Caddyfile
  cp "$B/docker-compose.override.yml" docker-compose.override.yml
  sed -i '/^RAMON_PAINEL_AGENTES_/d' chatwoot.env
  docker compose up -d caddy
  web_sobe
  systemctl disable --now esteira-vision-proxy.socket esteira-vision-proxy.service
  echo "desfeito a partir de $B"
  exit 0
fi

EMAIL="${1:?informe o e-mail do login no hub}"

# 1. Cópia do que muda. A primeira cópia é a que o --desfazer usa.
B="$BASE/.painel-agentes-bak-$(date +%Y%m%d%H%M%S)"
mkdir -p "$B"
cp -p Caddyfile docker-compose.override.yml chatwoot.env "$B/"

# 2. Ponte até o painel.
install -m 644 "$AQUI/esteira-vision-proxy.socket" "$AQUI/esteira-vision-proxy.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now esteira-vision-proxy.socket

# 3. Quem entra e onde está. Sem isso, o portão recusa todo mundo.
sed -i '/^RAMON_PAINEL_AGENTES_/d' chatwoot.env
printf 'RAMON_PAINEL_AGENTES_EMAILS=%s\nRAMON_PAINEL_AGENTES_URL=%s\n' "$EMAIL" "$URL" >> chatwoot.env

# 4. Caddy e compose, validados antes de valer.
grep -qF "$SITE" Caddyfile || cat "$AQUI/Caddyfile.trecho" >> Caddyfile
if ! grep -q 'esteira-vision-proxy' docker-compose.override.yml; then
  sed -i '/^volumes:/i\  # Painel dos agentes (ADR 0013): porta própria e socket até o foreman-vision.\n  caddy:\n    ports:\n      - "8443:8443"\n    volumes:\n      - /run/esteira-vision-proxy:/run/esteira-vision-proxy\n' docker-compose.override.yml
fi
docker compose config -q
if ! docker run --rm -v "$BASE/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null; then
  cat "$B/Caddyfile" > Caddyfile
  echo "Caddyfile inválido: restaurei a cópia e parei." >&2
  exit 1
fi

docker compose up -d caddy
web_sobe

# 5. Conferência: sem sessão o painel recusa; o hub segue no ar.
for _ in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' https://chat.ramonantonio.adv.br/app/login)" = 200 ] && break
  sleep 5
done
echo "hub (espera 200): $(curl -s -o /dev/null -w '%{http_code}' https://chat.ramonantonio.adv.br/app/login)"
echo "painel sem sessão (espera 401): $(curl -s -o /dev/null -w '%{http_code}' "$URL")"
echo "cópia em $B"
