#!/usr/bin/env bash
# Liga o painel dos agentes na VPS (ADR 0013). Rode como root, com o hub já na versão que tem o portão:
#   bash instalar.sh <e-mail do login no hub>     liga (pode repetir, não duplica nada)
#   bash instalar.sh --desfazer                   tira só o que este script pôs
# Teste do próprio script: test_instalar.sh.
set -Eeuo pipefail

BASE="${PAINEL_BASE:-/opt/intranet-ramon}"
UNITS="${PAINEL_UNITS:-/etc/systemd/system}"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL=https://chat.ramonantonio.adv.br:8443/
cd "$BASE"

# Tira o bloco marcado. Reescreve por dentro: o Caddyfile é montado como arquivo, e trocar o inode cegaria o container.
tirar_bloco() {
  local limpo
  limpo="$(sed '/# >>> painel-agentes/,/# <<< painel-agentes/d' "$1")"
  printf '%s\n' "$limpo" > "$1"
}

if [ "${1:-}" = "--desfazer" ]; then
  tirar_bloco Caddyfile
  tirar_bloco docker-compose.override.yml
  sed -i '/^RAMON_PAINEL_AGENTES_/d;/^RAMON_ESTEIRA_APROVACOES_TOKEN=/d' chatwoot.env
  docker compose up -d caddy chatwoot-web
  systemctl disable --now esteira-vision-proxy.socket esteira-vision-proxy.service
  rm -f "$UNITS/esteira-vision-proxy.socket" "$UNITS/esteira-vision-proxy.service"
  systemctl daemon-reload
  echo "desfeito"
  exit 0
fi

EMAIL="${1:?informe o e-mail do login no hub}"

grep -q '^volumes:' docker-compose.override.yml || { echo "!! override sem a seção volumes: parei" >&2; exit 1; }

# 1. Configuração nova, validada antes de valer. Falhou, volta como estava e nada é recriado.
B="$(mktemp -d)"
cp -p Caddyfile docker-compose.override.yml "$B/"
voltar() {
  cat "$B/Caddyfile" > Caddyfile
  cat "$B/docker-compose.override.yml" > docker-compose.override.yml
  echo "!! falhou: Caddyfile e override voltaram ao que eram" >&2
}
trap voltar ERR

tirar_bloco Caddyfile
tirar_bloco docker-compose.override.yml
if grep -q '^  caddy:' docker-compose.override.yml; then
  echo "!! override já define o caddy: junte à mão e rode de novo" >&2
  false
fi
{ echo; cat "$AQUI/Caddyfile.trecho"; } >> Caddyfile
awk -v trecho="$AQUI/override.trecho" '/^volumes:/ && !feito { while ((getline linha < trecho) > 0) print linha; feito = 1 } { print }'   docker-compose.override.yml > "$B/override.novo"
cat "$B/override.novo" > docker-compose.override.yml
docker compose config -q
docker run --rm -v "$BASE/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null
trap - ERR

# 2. Ponte até o painel.
install -m 644 "$AQUI/esteira-vision-proxy.socket" "$AQUI/esteira-vision-proxy.service" "$UNITS/"
systemctl daemon-reload
systemctl enable --now esteira-vision-proxy.socket

# 3. Quem entra e onde está. Sem isso, o portão recusa todo mundo.
sed -i '/^RAMON_PAINEL_AGENTES_/d' chatwoot.env
printf 'RAMON_PAINEL_AGENTES_EMAILS=%s\nRAMON_PAINEL_AGENTES_URL=%s\n' "$EMAIL" "$URL" >> chatwoot.env
# Token do hook de aprovações (ADR 0014): a esteira pega daqui pelo preparar-env.sh.
grep -q '^RAMON_ESTEIRA_APROVACOES_TOKEN=' chatwoot.env || printf 'RAMON_ESTEIRA_APROVACOES_TOKEN=%s\n' "$(openssl rand -hex 32)" >> chatwoot.env

docker compose up -d caddy chatwoot-web

# 4. Conferência: sem sessão o painel recusa; o hub segue no ar.
for _ in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' https://chat.ramonantonio.adv.br/app/login)" = 200 ] && break
  sleep 5
done
echo "hub (espera 200): $(curl -s -o /dev/null -w '%{http_code}' https://chat.ramonantonio.adv.br/app/login)"
echo "painel sem sessão (espera 401): $(curl -s -o /dev/null -w '%{http_code}' "$URL")"
