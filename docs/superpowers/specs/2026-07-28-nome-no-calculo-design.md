# Nome do segurado no cálculo rápido — design

**Data:** 2026-07-28 · **Aprovado por:** Eduardo (conversa 28/07)

## Problema

A tela Cálculos abre direto na calculadora (PR #112) e todo cálculo vira registro
no histórico (PR #113), mas o nome do segurado só existe quando vem do contato do
hub ou do cabeçalho do CNIS. Numa consulta rápida — pessoa que ainda não é
cliente, muitas vezes sem CNIS anexado — o cálculo entra no histórico "sem nome"
e não dá pra reencontrar pela busca.

## Decisão (Eduardo, via AskUserQuestion)

**Só o cálculo com nome.** Nada de criar contato/lead — se a pessoa fechar,
entra no funil pelo caminho normal.

## Solução

Campo **"Nome (opcional)"** no modo calculadora da tela Cálculos. O que for
digitado acompanha cada requisição de cálculo e vira o `segurado_nome` do
registro no histórico, com prioridade sobre o nome extraído do CNIS. Sem digitar
nada, comportamento atual (nome do CNIS, ou em branco).

### Backend — 1 ponto

`RegistraCalculo#nome_do_segurado` (concern usado pelos 6 controllers de cálculo):

```ruby
params[:segurado_nome].presence || @lead.contact&.name.presence || @lead.cnis&.dig('segurado_nome')
```

Leitura direta de `params` (não é mass-assignment); nenhum controller muda.
Sem migração — a coluna `segurado_nome` já existe.

### Front

- `Calculos.vue`: ref `seguradoNome` + input no modo calculadora (acima do
  simulador); entrar na calculadora limpa o campo (mesmo princípio da entrada
  limpa do CNIS); `reabrirCalculo` repõe `item.segurado_nome` quando o cálculo
  reabre no rascunho.
- `LeadSimulador.vue`: prop `seguradoNome` (String, default `''`), anexada como
  `segurado_nome` nos payloads dos POSTs de cálculo (simular, painel,
  elegibilidade, pensão, maternidade, planejamento). O prop **só é passado na
  instância do rascunho** — cálculo aberto por lead real nunca herda nome
  digitado (lá vale o contato, como hoje).

### Fora de escopo

Criar contato a partir do nome · nome no caso de rascunho (é reutilizado e
limpo a cada entrada) · busca (já existe, `GET /calculos?q=`).

## Testes

- Request spec: cálculo com `segurado_nome` no param grava o histórico com esse
  nome (prioridade sobre CNIS/contato).
- Vitest `Calculos.spec.js`: input aparece no modo calculadora; reabrir repõe o
  nome; abrir a calculadora limpa.
