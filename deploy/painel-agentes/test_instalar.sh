#!/usr/bin/env bash
# Exercita instalar.sh numa cópia de mentira da VPS: docker, systemctl e curl são stubs.
#   bash deploy/painel-agentes/test_instalar.sh
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PAINEL_BASE="$TMP/vps" PAINEL_UNITS="$TMP/units" STUB_LOG="$TMP/log" PAINEL_SEGREDO_ARQ="$TMP/painel.env"
mkdir -p "$PAINEL_BASE" "$PAINEL_UNITS" "$TMP/bin"
: > "$STUB_LOG"
printf 'PAINEL_SEGREDO=abc123\n' > "$PAINEL_SEGREDO_ARQ"

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
confere() { [ "$(grep -c -e "$1" "$2")" = "$3" ] || falha "$2 deveria ter $3x: $1"; }

prepara
bash "$AQUI/instalar.sh" eduardo@example.com > /dev/null
bash "$AQUI/instalar.sh" eduardo@example.com > /dev/null
confere 'chat.ramonantonio.adv.br:8443' "$PAINEL_BASE/Caddyfile" 1
confere '"8443:8443"' "$PAINEL_BASE/docker-compose.override.yml" 1
confere '^RAMON_PAINEL_AGENTES_EMAILS=eduardo@example.com$' "$PAINEL_BASE/chatwoot.env" 1
confere 'up -d caddy' "$STUB_LOG" 2
confere '^RAMON_ESTEIRA_APROVACOES_TOKEN=' "$PAINEL_BASE/chatwoot.env" 1
confere '^RAMON_AGENTES_DECISORES_EMAILS=eduardo@example.com$' "$PAINEL_BASE/chatwoot.env" 1
echo "ok: instala e repete sem duplicar; quem vê também decide por padrão"

bash "$AQUI/instalar.sh" ve@example.com decide@example.com > /dev/null
confere '^RAMON_PAINEL_AGENTES_EMAILS=ve@example.com$' "$PAINEL_BASE/chatwoot.env" 1
confere '^RAMON_AGENTES_DECISORES_EMAILS=decide@example.com$' "$PAINEL_BASE/chatwoot.env" 1
confere '^RAMON_AGENTES_DECISORES_EMAILS=' "$PAINEL_BASE/chatwoot.env" 1
echo "ok: decisores à parte"

# Cabeçalho forjado pelo navegador (ADR 0016): os três caem antes do forward_auth, dentro de um route,
# que é o que garante a ordem escrita no Caddy.
linha() { grep -n -- "$1" "$PAINEL_BASE/Caddyfile" | head -1 | cut -d: -f1; }
for cab in X-Painel-Usuario X-Painel-Escreve X-Painel-Segredo; do
  [ -n "$(linha "request_header -$cab$")" ] || falha "Caddyfile não remove $cab"
  [ "$(linha "route {")" -lt "$(linha "request_header -$cab$")" ] || falha "remoção de $cab fora do route"
  [ "$(linha "request_header -$cab$")" -lt "$(linha "forward_auth ")" ] || falha "remoção de $cab depois do forward_auth"
done
confere 'copy_headers X-Painel-Usuario X-Painel-Escreve$' "$PAINEL_BASE/Caddyfile" 1
confere 'header_up X-Painel-Segredo {\$PAINEL_SEGREDO}$' "$PAINEL_BASE/Caddyfile" 1
confere '^      - /etc/esteira/painel.env$' "$PAINEL_BASE/docker-compose.override.yml" 1
confere "caddy validate" "$STUB_LOG" 3
confere "--env-file $PAINEL_SEGREDO_ARQ .*caddy validate" "$STUB_LOG" 3
echo "ok: Caddy apaga a identidade do navegador, copia a do portão e manda a senha"

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

for conteudo in ausente 'PAINEL_SEGREDO=' 'OUTRA=1'; do
  prepara
  : > "$STUB_LOG"
  if [ "$conteudo" = ausente ]; then rm -f "$PAINEL_SEGREDO_ARQ"; else printf '%s\n' "$conteudo" > "$PAINEL_SEGREDO_ARQ"; fi
  if bash "$AQUI/instalar.sh" eduardo@example.com > /dev/null 2> "$TMP/erro"; then falha "deveria parar sem a senha ($conteudo)"; fi
  grep -q 'rode antes o install.sh da esteira' "$TMP/erro" || falha "erro sem a instrução ($conteudo)"
  cmp -s "$PAINEL_BASE/Caddyfile" "$TMP/Caddyfile.original" || falha "Caddyfile mudou sem a senha"
  cmp -s "$PAINEL_BASE/docker-compose.override.yml" "$TMP/override.original" || falha "override mudou sem a senha"
  cmp -s "$PAINEL_BASE/chatwoot.env" "$TMP/env.original" || falha "env mudou sem a senha"
  [ ! -s "$STUB_LOG" ] || falha "chamou docker/systemctl sem a senha"
done
echo "ok: sem a senha da esteira, para antes de mexer em qualquer coisa"
