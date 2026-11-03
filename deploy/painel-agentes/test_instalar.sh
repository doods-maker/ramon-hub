#!/usr/bin/env bash
# Exercita instalar.sh numa cópia de mentira da VPS: docker, systemctl e curl são stubs.
#   bash deploy/painel-agentes/test_instalar.sh
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PAINEL_BASE="$TMP/vps" PAINEL_UNITS="$TMP/units" STUB_LOG="$TMP/log"
mkdir -p "$PAINEL_BASE" "$PAINEL_UNITS" "$TMP/bin"
: > "$STUB_LOG"

for cmd in docker systemctl; do
  cat > "$TMP/bin/$cmd" <<'EOF'
#!/usr/bin/env bash
echo "$(basename "$0") $*" >> "$STUB_LOG"
case "$*" in *"caddy validate"*) [ -z "${FALHAR_VALIDACAO:-}" ] ;; esac
EOF
done
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
case "$*" in *:8443*) printf 401 ;; *) printf 200 ;; esac
EOF
chmod +x "$TMP"/bin/*
export PATH="$TMP/bin:$PATH"

prepara() {
  printf 'chat.ramonantonio.adv.br {\n\treverse_proxy chatwoot-web:3000\n}\n' > "$PAINEL_BASE/Caddyfile"
  printf 'services:\n  whisper:\n    image: x\n\nvolumes:\n  whisper_data:\n' > "$PAINEL_BASE/docker-compose.override.yml"
  printf 'OUTRA=1\n' > "$PAINEL_BASE/chatwoot.env"
  cp "$PAINEL_BASE/Caddyfile" "$TMP/Caddyfile.original"
  cp "$PAINEL_BASE/docker-compose.override.yml" "$TMP/override.original"
  cp "$PAINEL_BASE/chatwoot.env" "$TMP/env.original"
}
falha() { echo "FALHOU: $*" >&2; exit 1; }
confere() { [ "$(grep -c "$1" "$2")" = "$3" ] || falha "$2 deveria ter $3x: $1"; }

prepara
bash "$AQUI/instalar.sh" eduardo@example.com > /dev/null
bash "$AQUI/instalar.sh" eduardo@example.com > /dev/null
confere 'chat.ramonantonio.adv.br:8443' "$PAINEL_BASE/Caddyfile" 1
confere '"8443:8443"' "$PAINEL_BASE/docker-compose.override.yml" 1
confere '^RAMON_PAINEL_AGENTES_EMAILS=eduardo@example.com$' "$PAINEL_BASE/chatwoot.env" 1
confere 'up -d caddy' "$STUB_LOG" 2
confere '^RAMON_ESTEIRA_APROVACOES_TOKEN=' "$PAINEL_BASE/chatwoot.env" 1
echo "ok: instala e repete sem duplicar"

printf '\n# alteracao feita depois\n' >> "$PAINEL_BASE/Caddyfile"
bash "$AQUI/instalar.sh" --desfazer > /dev/null
confere '8443' "$PAINEL_BASE/Caddyfile" 0
confere 'alteracao feita depois' "$PAINEL_BASE/Caddyfile" 1
cmp -s "$PAINEL_BASE/docker-compose.override.yml" "$TMP/override.original" || falha "override não voltou ao original"
cmp -s "$PAINEL_BASE/chatwoot.env" "$TMP/env.original" || falha "env não voltou ao original"
echo "ok: desfazer tira só o que foi instalado"

prepara
: > "$STUB_LOG"
if FALHAR_VALIDACAO=1 bash "$AQUI/instalar.sh" eduardo@example.com > /dev/null 2>&1; then falha "deveria parar com Caddyfile inválido"; fi
cmp -s "$PAINEL_BASE/Caddyfile" "$TMP/Caddyfile.original" || falha "Caddyfile não voltou"
cmp -s "$PAINEL_BASE/docker-compose.override.yml" "$TMP/override.original" || falha "override não voltou"
cmp -s "$PAINEL_BASE/chatwoot.env" "$TMP/env.original" || falha "env foi alterado"
confere 'up -d' "$STUB_LOG" 0
echo "ok: configuração inválida não altera nada nem recria container"

prepara
printf 'services:\n  caddy:\n    ports: []\n\nvolumes:\n  x:\n' > "$PAINEL_BASE/docker-compose.override.yml"
if bash "$AQUI/instalar.sh" eduardo@example.com > /dev/null 2>&1; then falha "deveria recusar override que já tem caddy"; fi
echo "ok: recusa override que já define o caddy"
