#!/usr/bin/env python3
"""Runner do agente do hub — recebe POST do ramon-hub (nota privada @claude do
Eduardo), roda `claude -p --bare` só-leitura e faz as escritas determinísticas
(Drive → tarefa ADVBOX via MCP do hub → nota privada → trilha).
Spec: ramon-hub/docs/superpowers/specs/2026-08-17-agente-hub-design.md
Stdlib only. Roda como usuário `agente` via systemd (deploy/agente-hub/agente-hub.service)."""
import datetime as dt, hmac, json, os, re, subprocess, sys, threading, queue, time, urllib.request, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TZ = dt.timezone(dt.timedelta(hours=-3))  # America/Sao_Paulo sem DST


def parse_pedido(content):
    txt = re.sub(r'^\s*@claude\b[:,]?\s*', '', content or '', flags=re.I)
    esforco = 'medium' if re.search(r'#pesado\b', txt, re.I) else 'low'
    m = re.search(r'#tese:(\S+)', txt, re.I)
    tese = m.group(1) if m else None
    txt = re.sub(r'#pesado\b|#tese:\S+', '', txt, flags=re.I)
    return {'pedido': re.sub(r'\s+', ' ', txt).strip(), 'esforco': esforco, 'tese': tese}


def aceita(payload, secret_hdr, cfg):
    if not hmac.compare_digest(str(secret_hdr or ''), str(cfg.WEBHOOK_SECRET)):
        return False, 'segredo'
    if (payload.get('sender_email') or '').lower() != cfg.EDUARDO_EMAIL.lower():
        return False, 'remetente'
    if not re.match(r'^\s*@claude\b', payload.get('content') or '', re.I):
        return False, 'sem @claude'
    return True, 'ok'


class Cap:
    def __init__(self, state_dir, cap_dia):
        self.dir, self.cap = state_dir, int(cap_dia)
        os.makedirs(state_dir, exist_ok=True)

    def _hoje(self):
        return dt.datetime.now(TZ).date().isoformat()

    def _arq(self):
        return os.path.join(self.dir, f'contador-{self._hoje()}')

    def usados(self):
        try:
            with open(self._arq()) as f:
                return int(f.read() or 0)
        except FileNotFoundError:
            return 0

    def pausado(self):
        try:
            with open(os.path.join(self.dir, 'pausado-ate')) as f:
                return f.read().strip() >= self._hoje()
        except FileNotFoundError:
            return False

    def pode(self):
        return not self.pausado() and self.usados() < self.cap

    def conta(self):
        n = self.usados() + 1  # ler ANTES de abrir em 'w' (o open trunca o arquivo)
        with open(self._arq(), 'w') as f:
            f.write(str(n))

    def pausar_ate_amanha(self):
        amanha = (dt.datetime.now(TZ).date() + dt.timedelta(days=1)).isoformat()
        with open(os.path.join(self.dir, 'pausado-ate'), 'w') as f:
            f.write(amanha)


def detecta_limite(texto):
    return bool(re.search(r'usage limit|rate limit|limit reached|\b429\b|out of extra usage', texto or '', re.I))


def formatar_nota(status, duracao_s, resposta, acoes):
    cab = f'🤖 Claude · {status} · {int(round(duracao_s))}s'
    linhas = '\n'.join(f"{a.get('tipo')} → {a.get('ref')}" for a in (acoes or [])) if acoes else 'nenhuma escrita'
    return f'{cab}\n{resposta.strip()}\n— Ações: {linhas}'
