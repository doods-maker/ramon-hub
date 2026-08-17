# agente-hub

Runner do "agente do hub". O ramon-hub faz `POST /hub` aqui quando o Eduardo
escreve uma nota privada começando com `@claude`. O runner roda `claude -p`
isolado — usuário `agente` na VPS, `--allowedTools` só de leitura (Read/Grep/Glob
+ tools `mcp__advbox__*` de consulta), `--strict-mcp-config` e cwd num diretório
vazio (`work/`) — e faz as escritas determinísticas: arquivo no Drive → tarefa ADVBOX
via MCP do hub → nota privada de volta na conversa → trilha em `execucoes`.

Só stdlib do Python 3. Roda na VPS como usuário `agente` via systemd
(`agente-hub.service`), escutando só na rede interna do Docker.

- Config: copie `env.example` para `/opt/agente-hub/env` (0600) e preencha.
- Instalação na VPS: `install.sh` (Task 9).
- Testes: `cd deploy/agente-hub && python -m unittest -v test_agente_hub.py`
