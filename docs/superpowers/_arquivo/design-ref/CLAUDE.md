# Ramon Antonio — Fork do Chatwoot + Intranet

> Documento de contexto para o **Claude Code**. Descreve a visão, a base de design já
> prototipada e as regras do produto. **Leia tudo antes de gerar código** e, no fim,
> **faça perguntas e proponha um brainstorming** de funcionalidades (ver a seção final).

---

## 1. O que é o projeto

Estou criando um **fork do Chatwoot** e quero embutir a minha **intranet** dentro dele —
tudo no mesmo app, com a marca do escritório **Ramon Antonio Advogados** (Direito
Previdenciário / INSS, Tubarão-SC).

A ideia central: **um único produto** onde o time alterna entre dois mundos por um
**trilho lateral**:

1. **Conversas (Chatwoot)** — o atendimento que já existe, apenas rebrandizado.
2. **Intranet** — um painel novo de gestão comercial/jurídica (Centro de Comando, Funil,
   SDR, etc.).

A base visual e de navegação já está prototipada (ver arquivos na seção 6). **Use o
protótipo como fonte de verdade de UX e marca**, e reproduza no stack do fork.

---

## 2. Arquitetura de navegação

### Trilho lateral (≈78px, fixo, escuro)
Troca o app inteiro **sem recarregar a página**. Dividido em dois grupos:

- **INTERNOS**
  - **Conversas** → módulo Chatwoot (atendimento)
  - **Intranet** → Centro de Comando e demais módulos
- **EXTERNOS** (abrem em **nova aba** — `target="_blank"`)
  - AdvBox, Meu INSS, Google Agenda — **lista configurável** (quero poder adicionar
    outros atalhos externos que facilitem o dia a dia)

No rodapé do trilho: configurações + avatar do usuário.

### Modo Conversas (Chatwoot rebrandizado)
- Sidebar de navegação (Caixa de Entrada, Conversas → Todas/Menções/Participantes/Não
  atendidas/Canais, **Kanban Board**, Capitão, Contatos, Relatórios, Campanhas, Central
  de Ajuda, Configurações).
- Lista de conversas (abas Minhas / Não atribuídas / Todos).
- Conversa aberta dividida em **duas metades**: mensagens à esquerda + **Painel do Lead**
  ancorado à direita (ver seção 4).

### Modo Intranet
- Sidebar escura por seções: **COMERCIAL** (Centro de Comando, Funil de Leads, Painel do
  SDR, Pra fechar, Agenda, Modelos, Conversas), **JURÍDICO** (Triagem de Iniciais,
  Histórico), **MARKETING** (Marketing, Campanhas, Relatórios), **INTELIGÊNCIA** (Agentes
  de IA, Base de Conhecimento, Prompts), **GESTÃO** (Equipe).
- Telas já desenhadas: **Centro de Comando** (dashboard com KPIs, funil-resumo, agenda,
  pra-fechar), **Funil de Leads** (kanban) e **Painel do SDR** (ligações, taxa de
  conexão, ranking, gráfico). As demais são pontos de partida.

---

## 3. Kanban espelhado (regra importante)

O **Kanban Board** do Chatwoot e o **Funil de Leads** da Intranet são o **MESMO board**
— uma **fonte de dados única**. Mover um card num lugar reflete no outro em tempo real.

- **Colunas/etapas:** Novo · Qualificação · Reunião agendada · Reunião realizada ·
  Negociação · Última chance · Fechado · Perdido.
- **Card:** nome do lead, tipo de benefício (Aposentadoria, BPC/LOAS, Auxílio-doença,
  Pensão por morte…), **prioridade** (Alta/Média/Baixa) e botão **Abrir conversa**.
- **Drag & drop** entre colunas (já implementado no protótipo).
- **Abrir conversa** abre uma **mini janela de WhatsApp flutuante** no canto inferior
  direito, sem sair do kanban.

> No fork, modelar isso como uma entidade `Lead/Deal` única com `stage`, consumida pelos
> dois módulos (provavelmente um modelo no backend + realtime/websocket para o espelho).

---

## 4. Painel do Lead (dentro da conversa)

Fica fixo em **metade da conversa** (não em tela cheia) para o **SDR e o closer**
analisarem enquanto atendem. Tem **abas**:

- **Resumo** — temperatura (Quente/Morno/Frio), etapa no funil, qualificação (tipo de
  benefício, situação no INSS, origem), checklist de qualificação, dados do contato,
  atribuição (SDR + Closer), próxima ação e notas internas.
- **Histórico** — timeline das interações (lead criado → contato → reunião → negociação →
  proposta).
- **Documentos** — CNIS, RG/CPF, comprovantes etc., com status Recebido/Pendente e
  "Anexar documento".

---

## 5. Marca & design (Ramon Antonio)

Estética **escura + bronze**, sóbria e corporativa. **Não usar segunda cor** (sem azul,
roxo, vermelho ou cinza frio) — inclusive prioridade "Alta" é **bronze sólido**, não
vermelho.

| Token | Valor |
|---|---|
| Fundo do app | `#120d09` |
| Trilho | `#0c0907` |
| Sidebar | `#15100b` / `#16110c` |
| Cards/superfícies | `#1f1812` · `#211a13` · colunas `#17120d` |
| Acento (ativo, ícones) | `#c4a882` (bronze-300) |
| Primária (botões) | `#754d2a` (bronze-600) · hover `#5c3c22` |
| Texto sobre escuro | `#ede0c8` (principal) · `#9c876a` (secundário) |
| Bordas | `rgba(237,224,200,0.07–0.1)` |

- **Tipografia:** **Cormorant Garamond** (serif) para títulos e números; **Inter** para
  UI/corpo. Eyebrows em UPPERCASE com tracking largo.
- **Ícones:** linha 1.6 estilo **Lucide**. **Sem emoji** em contexto institucional.
- **Cantos:** 8/11/14/16px; pílulas 999px para badges.
- **Sombras:** quentes (`rgba(59,32,16,…)` / pretas no escuro), nunca cinza/azul.
- Tokens completos em `_ds/ramon-antonio-brand-…/tokens/`.

### Conteúdo / tom
PT-BR, trata o cliente por "você", transparente ("você acompanha cada etapa"). **Compliance OAB (Prov. 205/2021):** conteúdo público é só informativo — nada de captação,
promessa de resultado ou valores de honorários. (O CRM interno pode exibir métricas
operacionais normalmente.)

---

## 6. Arquivos deste pacote

- **`Ramon Antonio Hub.dc.html`** — protótipo-fonte completo (lógica + template). É a
  referência principal de UX/marca.
- **`Ramon Antonio Hub — standalone.html`** — mesmo protótipo num único arquivo offline;
  abra no navegador para navegar/clicar.
- **`Documentação — Fork.dc.html`** — as telas lado a lado + painel de especificação.
- **`assets/`** — logo e monograma.
- **`_ds/ramon-antonio-brand-…/`** — tokens da marca (cores, tipografia, espaçamento).

> O `.dc.html` é um formato de componente próprio (não é o stack do fork). **Use-o como
> referência visual/funcional**, não para copiar o código literalmente.

---

## 7. Stack do fork — onde cada coisa entra

O fork é um **Chatwoot** (Ruby on Rails no backend + **Vue 3 / Vite / Vuex** no
dashboard). O mapa abaixo segue a árvore padrão do Chatwoot; **se o meu fork divergiu,
peça a árvore de diretórios (ou o repositório) antes de codar.**

### ⚠️ Antes de codar: confirme os caminhos no MEU repositório
Eu posso já ter alterado a estrutura e **não sei exatamente onde está cada coisa**. Então,
antes de propor qualquer mudança:

1. **Inspecione o repo de verdade.** Rode uma varredura e localize os arquivos reais em
   vez de assumir os caminhos abaixo. Buscas úteis:
   - Navegação/sidebar: `rg -l "PrimaryNavItem|Sidebar" app/javascript`
   - Rotas do dashboard: `fd . app/javascript/dashboard/routes`
   - Store: `fd . app/javascript/dashboard/store/modules`
   - Painel da conversa: `rg -l "ContactPanel|ConversationBox" app/javascript`
   - Branding: `rg -n "INSTALLATION_NAME|BRAND_NAME|LOGO" config/`
   - i18n PT-BR: `fd pt_BR app/javascript/dashboard/i18n`
   - Versão/stack: leia `package.json`, `Gemfile` e `config/` para confirmar Vue 3 + Vite
     (e se já usam Pinia em vez de Vuex em alguma área).
2. **Compare com o mapa de referência (abaixo)** e me diga, em forma de checklist, **o que
   bate e o que mudou** no meu fork — com os caminhos reais que você encontrou.
3. **Só depois proponha o plano.** Se algo não existir ou estiver diferente do esperado,
   **pergunte antes de criar/renomear** arquivos.

> Trate os caminhos da próxima seção como **referência da árvore _padrão_ do Chatwoot**,
> não como verdade sobre o meu fork. A fonte da verdade é o código do repositório.

### Mapa de referência (árvore padrão do Chatwoot)

#### Frontend (dashboard SPA — `app/javascript/dashboard/`)
- **Trilho lateral (Internos/Externos):** estender a navegação primária em
  `components/layout/sidebarComponents/Primary.vue` + `PrimaryNavItem.vue`. Adicionar os
  itens **Conversas** e **Intranet** (Internos) e a lista configurável de **Externos**
  (links com `target="_blank"`, vindos de config do usuário/conta).
- **Alternância Conversas ⇄ Intranet:** rota/área no router `routes/dashboard/`. A
  Intranet vira uma seção nova (ex.: `routes/dashboard/intranet/`) com a própria sidebar
  (`Secondary.vue` análogo) e páginas (Centro de Comando, Funil, SDR…). Trocar de modo é
  só navegação — sem reload.
- **Kanban Board (Conversas):** novo componente em
  `components/widgets/conversation/` (ou um route próprio) — `KanbanBoard.vue`.
- **Funil de Leads (Intranet):** mesma view do kanban, consumindo o **mesmo store**.
  Drag & drop com `vuedraggable`.
- **Painel do Lead:** estender o painel da conversa
  (`components/widgets/conversation/ContactPanel.vue` / `conversation/contact/`) com um
  componente de abas (Resumo / Histórico / Documentos) ocupando ~metade da conversa.
- **Mini-chat flutuante:** widget próprio montado no nível do app.
- **Marca/tema:** tokens SCSS em `assets/scss/` (variáveis de cor) + logo/nome via
  `config/installation_config.yml` (`LOGO`, `LOGO_DARK`, `BRAND_NAME`,
  `INSTALLATION_NAME`). Tema escuro + bronze conforme seção 5.
- **i18n:** textos em `i18n/locale/pt_BR/`.

#### Backend (Rails)
- **Entidade Lead/Deal única** (fonte do kanban espelhado): novo model
  `app/models/lead.rb` (ou `deal.rb`) com `stage`, `priority`, `benefit_type`,
  `sdr_id`, `closer_id`, associação a `Contact`/`Conversation`. Migration +
  `app/controllers/api/v1/accounts/leads_controller.rb` + serializer.
- **Espelho em tempo real Chatwoot ⇄ Intranet:** o mesmo registro de Lead alimenta os
  dois módulos; mudanças de `stage` propagam via **ActionCable** (já usado pelo
  Chatwoot) para atualizar kanban e funil ao vivo.
- **Store (Vuex):** módulo `store/modules/leads/` consumido pelas duas telas — é o que
  garante o espelhamento no front.
- **Documentos do lead:** Active Storage anexado ao Lead/Contact, com status
  (recebido/pendente).

> **Importante:** o módulo de **Conversas** é o Chatwoot existente — apenas rebrandizado.
> Não reescreva a lógica de atendimento; adicione a Intranet e o Lead/Deal **ao redor**
> dele, reaproveitando Contact, Conversation, Inbox e ActionCable.

---

## 8. Como quero trabalhar com você (Claude Code)

1. **Não saia codando tudo de uma vez.** Primeiro confirme comigo o **stack do fork**
   (Chatwoot é Ruby on Rails + Vue/Vite) e onde cada coisa entra.
2. Trate este protótipo como o **alvo de UX**; me ajude a traduzir para o código do fork
   de forma incremental, começando pelo que der mais valor.
3. **Faça perguntas** sempre que algo estiver ambíguo.

### Pontos em aberto — quero fazer brainstorming com você
Me provoque com perguntas e sugestões sobre (entre outras):

- **Integrações:** AdvBox (sincronizar leads/processos?), Meu INSS/CNIS, WhatsApp oficial,
  e-mail, Google Agenda.
- **Automação/IA:** os módulos "Agentes de IA", "Base de Conhecimento" e "Prompts" da
  intranet — o que fazem? Triagem automática de iniciais? Respostas sugeridas no
  atendimento? Qualificação automática de lead?
- **Funil:** automações por etapa (ex.: mover para "Fechado" resolve a conversa; "Perdido"
  pede motivo), SLA/lembretes, distribuição de leads entre SDRs.
- **Permissões/papéis:** SDR, closer, advogado, gestor — quem vê o quê.
- **Jurídico:** como "Triagem de Iniciais" e "Histórico" se conectam ao funil comercial.
- **Relatórios/metas:** que indicadores o gestor precisa.
- **Dados:** modelo de Lead/Deal/Contato unificado e como espelhar Chatwoot ↔ Intranet.

> Quando eu te enviar isto, **comece resumindo o que entendeu, liste suas dúvidas e
> proponha um roadmap** em fases. Quero que este vire o melhor entregável possível.
