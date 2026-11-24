# BI do escritório dentro do hub (desenho curto)

*23/11/2026 · aprovado em conversa pelo Eduardo ("perfeito").*

## Por quê

O BI do escritório (`juridico\projetos\bi-escritorio`, um HTML só gerado pelo
`montar.py`) precisa ser visto pelo Ramon sem mandar arquivo a cada atualização.
O hub já tem login e o Ramon já é usuário administrador (criado em 31/10).

## O que é

- Aba nova **"BI do escritório"** na Intranet → Resultados, **só administrador**
  (rota com `permissions: ['administrator']` + policy `administrator?` no backend).
- Botão **"Enviar nova versão"**: o administrador sobe o `bi-escritorio.html`.
  O hub guarda **só a versão mais nova** e mostra quando e por quem foi enviada.
- A página mostra o BI numa moldura isolada.

## Restrições

- **O painel nunca vai para o git**: o repositório é público e o BI tem número de
  processo e valores. O arquivo vive só no armazenamento de anexos do hub
  (Active Storage → bucket R2 privado `ramon-hub-storage`).
- **Isolamento**: o HTML vem de fora e tem JavaScript. Ele roda em
  `<iframe sandbox="allow-scripts" srcdoc>` — sem `allow-same-origin`, então não
  lê cookie, token nem a API do hub. O backend devolve o HTML pela API autenticada
  (a moldura não manda cabeçalho de login, por isso `srcdoc` e não `src`).
- Upload aceita só `.html`/`text/html`, até 5 MB.
- Sem migração: `has_one_attached :ramon_bi` no `Account` (mesmo padrão do
  `contacts_export` que já existe).

## Abordagens

1. **Upload pelo hub, guardado no Active Storage (escolhida).** Sem chave nova,
   sem migração, sem dado no git.
2. Copiar o arquivo para a VPS por ssh e servir de lá. Descartada: cada
   atualização exigiria o Eduardo no terminal da VPS.
3. `montar.py` enviando sozinho por API com token. Fica para depois: pede chave
   nova; o botão resolve hoje.

## Preparado para abrir aos sócios (Eduardo, 23/11)

Hoje só administrador vê. Depois o Eduardo quer liberar para outros sócios sem
torná-los administradores. Por isso, já agora:
- **"Ver" e "enviar" são permissões separadas** na policy (`show?` × `update?`).
  Enviar fica sempre com administrador; ver é que vai crescer.
- **A regra de quem vê mora num lugar só no backend** (`RamonBiPolicy#show?`); a
  aba e a rota usam `adminOnly`/`administrator` só como espelho dela.
- **Próxima fatia (abrir aos sócios):** `show?` passa a aceitar uma lista de
  usuários liberados, e a aba troca `adminOnly` por uma flag liberada pelo backend
  (o mesmo mecanismo `soPainel` que o menu da Intranet já usa para o Painel dos
  agentes). Não se faz agora: sem a lista, a flag não teria o que liberar.

## Fora do escopo

- A lista de sócios liberados e a tela para editá-la (próxima fatia).
- Advogadas vendo só as causas delas (exigiria filtrar no servidor).
- Envio automático pelo `montar.py`.

## Do lado do BI (`bi-escritorio`)

- Dentro da moldura isolada `history.replaceState` pode lançar erro (origem nula):
  envolver em `try/catch` no `bi_template.html`, para a navegação entre páginas
  continuar funcionando.
