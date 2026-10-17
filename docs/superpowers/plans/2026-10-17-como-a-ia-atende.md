# "Como a IA atende" — plano de implementação

> **Para agentes que executam:** SUB-SKILL OBRIGATÓRIA: superpowers:subagent-driven-development (recomendado) ou
> superpowers:executing-plans, task a task. Os passos usam checkbox (`- [ ]`).

**Objetivo:** trocar os 7 modos do copiloto pelo Perfil da IA (Marcador na Trilha + Permissão por ação + Gatilhos por
Etapa), decidido por tese, por caixa e no Padrão do escritório, numa tela só: Inteligência → Como a IA atende.

**Arquitetura:** um módulo fundo `Ramon::PerfilIa` (em `app/`) resolve o perfil efetivo de uma conversa ou lead e
responde a todas as perguntas que hoje vão a `Ramon::CopilotoModo`. A decisão "envia ou rascunho" é a função pura
`PerfilIa.decidir`, usada pelo `ResponseBuilderJob`, pelo Testar e pelos specs. Os perfis ficam em
`accounts.settings['ia_atendimento']`; a Pausa, em `conversation.custom_attributes['ia_pausa']`. A tela nova lê e grava
por `resource :ramon_ia_atendimento`.

**Stack:** Rails 7.1 / Ruby 3.4 (fork Chatwoot v4.15.1), Postgres jsonb, `audited`, Vue 3 `<script setup>` + Tailwind,
RSpec, Vitest.

**Spec:** `docs/superpowers/specs/2026-10-17-como-a-ia-atende-design.md` (aprovada 17/10) + mockup
`2026-10-17-como-a-ia-atende-mockup.html` + ADR 0009 + `CONTEXT.md`. Leia os três antes da Task 1.

## Restrições globais

- **Código de regra só em `app/`.** Nada em `app/` pode depender de `enterprise/` (o CI de código aberto apaga a
  pasta). `enterprise/` pode chamar `app/`. Para caixa com assistente, use `inbox.try(:captain_assistant)`.
- **Etapas por `label`**: `fase-novo`, `fase-qualificacao`, `fase-reuniao-agendada`, `fase-reuniao-realizada`,
  `fase-negociacao`, `fase-ultima-chance`. Chave de Etapa = `label.presence || "id-#{id}"`. Ganho =
  `is_won`, Perdido = `is_lost`.
- **Valores de Permissão gravados:** `'s' | 'r' | 'n'`. Marcador: chave da Etapa, `'_inicio'` ou `'_fim'`.
- **A troca sobe com toda caixa real igual a hoje.** O padrão inicial é `Ramon::PerfilIa::INICIAL` (ver Task 1).
  Ligar perfil em caixa real é ação do Eduardo depois do smoke.
- **Desconto nunca.** Não existe chave de desconto gravável; a linha da tela é travada.
- **Texto que muda o que a IA diz (gatilhos) é gate do Eduardo.** A Task 7 só mergeia com o "aprovado" dele.
- **Ruby:** RuboCop 150 colunas, `class Ramon::X` compacto. Lint com `rubocop-vps <arquivos>` (não há Ruby local).
- **Vue:** Composition API, eventos camelCase, só Tailwind, kit `ramon/helpers/ui.js` + `components-next`. i18n em
  `en/ramon.json` **e** `pt_BR/ramon.json`.
- **Verificação:** specs rodam no CI do PR. Cada task escreve o spec antes do código. Commit por task; um PR por fase.
- **Entrega:** merge com CI 100 % verde. Deploy **por pacote**: Fases 1–4 juntas (um deploy + o rake de migração),
  Fase 5 num segundo deploy, Fase 6 só depois de o pacote 1 estar no ar. Registrar no doc de entrega com smoke em bloco
  por seção.
- **Commit:** a worktree tem junção `node_modules` → checkout principal e `.husky/_` copiado; o hook roda. Não pular
  o hook. Vitest **não** roda pela junção: testes JS só no CI; local roda `./node_modules/.bin/eslint <arquivos>`.
  Não há Ruby local: RSpec só no CI; lint Ruby com `rubocop-vps <arquivos>`. Conferir CRLF (`git diff
  --ignore-cr-at-eol`) — o Edit pode gravar CRLF.

## Pontos de revisão (o que nenhum teste de caminho feliz pega)

1. **Conversa sem lead, ou lead sem Etapa.** Vale a 1ª Etapa aberta; a IA não pode quebrar nem mandar sozinha além do
   que o perfil daria em Novo. Teste na Task 1 (`estado(nil)`).
2. **Marcador apontando para uma Etapa que foi apagada ou label desconhecido.** Trata como `'_inicio'` (nada sai
   sozinho além da logística). Teste na Task 1.
3. **`settings['ia_atendimento']` com lixo** (base inexistente, permissão `'x'`, tese de outra conta). Leitura cai na
   base/INICIAL; gravação pela API devolve 422 sem gravar nada. Testes nas Tasks 1 e 8.
4. **O turno que cruza o Marcador.** A resposta desse turno sai como saiu o início do turno (perfil capturado no
   começo do job), e o aviso sai uma vez por Marcador. Testes nas Tasks 3 e 5.
5. **Migração rodada duas vezes, ou com perfil já gravado pela tela.** Não sobrescreve nada; o relatório diz o que
   pulou. Teste na Task 6.

---

## Fase 1 — Motor `PerfilIa` + troca dos chamadores + migração (PR 1, só servidor)

### Task 1: `Ramon::PerfilIa` — leitura, permissões e estado da Etapa

**Files:**
- Create: `app/services/ramon/perfil_ia.rb`
- Modify: `app/models/concerns/lead_roteiro.rb` (entra `attr_accessor :perfil_ia_simulado`; `copiloto_modo` e
  `copiloto_modo_simulado` só saem na Task 5, junto com o `CopilotoModo`, para cada task deixar o CI verde)
- Test: `spec/services/ramon/perfil_ia_spec.rb`

**Interfaces:**
- Produces:
  - `Ramon::PerfilIa::CHAVE = 'ia_atendimento'`, `ACOES = %w[fora_do_horario pedir_documentos desqualificar
    mover_etapa marcar_reuniao citar_honorario logistica contrato_zapsign]`, `SEM_NUNCA = %w[fora_do_horario logistica]`,
    `INICIO = '_inicio'`, `FIM = '_fim'`, `PAUSAS = %w[pausada rascunho]`, `PAUSA = 'ia_pausa'`.
  - `GATILHOS` = lista ordenada de chaves `%w[pediu_pessoa juridica outra_area fora_do_tema honorario_de_novo nao_le
    irritado tem_advogado desconto clausula]` (os textos entram na Task 7).
  - `PRONTOS` = `{ 'cautelosa' => cfg, 'equilibrada' => cfg, 'acelerada' => cfg }` com os valores da tabela "Os três
    perfis prontos" da spec. Marcadores: `'fase-qualificacao'`, `'fase-reuniao-agendada'`, `'_fim'`. Gatilhos:
    Cautelosa = todos; Equilibrada = todos menos `nao_le`; Acelerada = `%w[pediu_pessoa juridica outra_area
    fora_do_tema desconto clausula]`.
  - `INICIAL = { 'base' => 'cautelosa', 'marcador' => '_inicio', 'permissoes' => { 'logistica' => 's',
    'fora_do_horario' => 's', 'citar_honorario' => 'r', 'contrato_zapsign' => 'r' } }` (spec, Migração).
  - `TOOLS_DA_ACAO = { 'pedir_documentos' => %w[solicitar_documento enviar_link_portal], 'citar_honorario' =>
    %w[simular_honorario], 'marcar_reuniao' => %w[horarios_livres agendar_reuniao], 'contrato_zapsign' =>
    %w[preparar_contrato_zapsign] }`.
  - `ACAO_DA_TOOL_DE_TEXTO = { 'simular_honorario' => 'citar_honorario', 'solicitar_documento' => 'pedir_documentos',
    'enviar_link_portal' => 'pedir_documentos', 'preparar_contrato_zapsign' => 'contrato_zapsign' }`.
  - `PerfilIa.de(registro) -> PerfilIa` — `registro` é `Conversation` ou `Lead`. Captura no momento da chamada:
    `conversa`, `lead`, `etapa` (`lead&.lead_stage`), `pausa`, `cfg`, `alvo` (`'tese:<id>' | 'caixa:<id>' | 'padrao'`
    = quem deu o cfg), `origem` (`:tese | :caixa | :padrao | :teste`).
  - `PerfilIa.cfg_salvo(account, tipo, id = nil) -> Hash | nil` (`tipo` em `'padrao' | 'teses' | 'caixas'`).
  - `PerfilIa.chave_da_etapa(lead_stage) -> String`.
  - Instância: `#marcador -> String`, `#permissao(acao) -> :sozinha | :rascunho | :nunca`, `#estado(etapa = @etapa) ->
    :sozinha | :rascunho | :fechado | :pausada`, `#tools_bloqueadas -> Array<String>`, `#gatilhos(etapa = @etapa) ->
    Array<String>`, `#direto?(acao) -> Boolean`, `#logistica_sai?(etapa = @etapa) -> Boolean`, `#nome -> String`, `#base -> String`,
    `#etapa`, `#alvo`, `#origem`, `#pausa`.

- [ ] **Step 1: Escrever o spec que falha**

```ruby
RSpec.describe Ramon::PerfilIa do
  let(:account) { create(:account) }
  # etapas do seed (Leads::SeedDefaultConfigService) — Novo … Última chance, Fechado, Perdido
  let(:etapa) { ->(label) { account.lead_stages.find_by(label: label) } }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:tese) { create(:thesis, account: account) }

  def gravar(alvos) = account.update!(settings: { 'ia_atendimento' => alvos })

  it 'sem nada gravado vale o INICIAL (igual a hoje)' do
    perfil = described_class.de(conversa)
    expect([perfil.origem, perfil.alvo, perfil.marcador]).to eq([:padrao, 'padrao', '_inicio'])
    expect(perfil.permissao('logistica')).to eq(:sozinha)
    expect(perfil.permissao('citar_honorario')).to eq(:rascunho)
  end

  it 'quem manda: tese (própria ou o padrão) → caixa só sem tese → padrão' do
    gravar('padrao' => { 'base' => 'cautelosa' }, 'caixas' => { inbox.id.to_s => { 'base' => 'acelerada' } },
           'teses' => { tese.id.to_s => { 'base' => 'equilibrada' } })
    lead = create(:lead, account: account, conversation: conversa)
    expect(described_class.de(conversa).base).to eq('acelerada')
    lead.update!(thesis: tese)
    expect(described_class.de(conversa).alvo).to eq("tese:#{tese.id}")
    account.update!(settings: account.settings.deep_merge('ia_atendimento' => { 'teses' => { tese.id.to_s => nil } }))
    expect(described_class.de(conversa.reload).alvo).to eq('padrao') # tese que segue o padrão não cai na caixa
  end

  it 'estado da Etapa pelo Marcador; Fechado = :fechado; Perdido e Pausa = :pausada' do
    gravar('padrao' => { 'base' => 'equilibrada' }) # marcador depois de Reunião agendada
    perfil = described_class.de(conversa)
    expect(perfil.estado(etapa['fase-reuniao-agendada'])).to eq(:sozinha)
    expect(perfil.estado(etapa['fase-reuniao-realizada'])).to eq(:rascunho)
    expect(perfil.estado(account.lead_stages.find_by(is_won: true))).to eq(:fechado)
    expect(perfil.estado(account.lead_stages.find_by(is_lost: true))).to eq(:pausada)
    expect(perfil.estado(nil)).to eq(:sozinha) # sem lead/etapa = 1ª etapa aberta
    conversa.update!(custom_attributes: { 'ia_pausa' => 'pausada' })
    expect(described_class.de(conversa).estado(etapa['fase-novo'])).to eq(:pausada)
  end

  it 'lixo gravado cai na base; marcador desconhecido = _inicio' do
    gravar('padrao' => { 'base' => 'xablau', 'marcador' => 'fase-apagada', 'permissoes' => { 'logistica' => 'x' } })
    perfil = described_class.de(conversa)
    expect(perfil.base).to eq('cautelosa')
    expect(perfil.estado(etapa['fase-novo'])).to eq(:rascunho)
    expect(perfil.permissao('logistica')).to eq(:rascunho) # o da Cautelosa
  end

  it 'nunca tira as Tools da ação; direto? exige sozinha E Etapa antes do Marcador' do
    gravar('padrao' => { 'base' => 'cautelosa', 'marcador' => '_fim', 'permissoes' => { 'marcar_reuniao' => 's' } })
    lead = create(:lead, account: account, conversation: conversa, lead_stage: etapa['fase-qualificacao'])
    perfil = described_class.de(lead)
    expect(perfil.tools_bloqueadas).to contain_exactly('simular_honorario', 'preparar_contrato_zapsign')
    expect(perfil.direto?('marcar_reuniao')).to be(true)
    expect(perfil.direto?('mover_etapa')).to be(false)
  end
end
```

- [ ] **Step 2: Rodar e ver falhar** — `rubocop-vps spec/services/ramon/perfil_ia_spec.rb`; o spec roda no CI do PR.
  Esperado no CI: `uninitialized constant Ramon::PerfilIa`.

- [ ] **Step 3: Implementar `Ramon::PerfilIa` em `app/services/ramon/perfil_ia.rb`**
  - Etapas abertas da conta (`where(is_won: false, is_lost: false)`, ordem do `default_scope`), memorizadas na
    instância. Índice do Marcador: `_inicio` = -1, `_fim` = última, label = posição dela; label que não está na lista
    = -1. Etapa é `:sozinha` se o índice dela ≤ índice do Marcador.
  - `permissao(acao)`: `cfg['permissoes'][acao]` se for `s|r|n` (e `n` não vale para `SEM_NUNCA`), senão o da base;
    base inválida = `'cautelosa'`. `'desconto'` → sempre `:nunca`.
  - `logistica_sai?` = sem pausa, estado da `etapa` diferente de `:fechado`/`:pausada`, e (`estado == :sozinha` ou
    `permissao('logistica') == :sozinha`).
  - `direto?(acao)` = sem pausa, `permissao(acao) == :sozinha` e `estado == :sozinha`.
  - `nome` = nome do perfil pronto (`'Cautelosa'`…) ou `'Personalizado'` quando o cfg difere da base (comparar com o
    valor efetivo de cada ação, marcador e gatilhos).
  - Lead sem conversa e com `perfil_ia_simulado` (Testar) → esse cfg, `origem :teste`.
  - Cada leitura de `settings` passa por um `normalizar(cfg)` privado (descarta chave e valor fora da lista).

- [ ] **Step 4: Rodar e ver passar** — CI do PR: `spec/services/ramon/perfil_ia_spec.rb` verde.

- [ ] **Step 5: Commit** — `feat(ia): Ramon::PerfilIa (leitura, permissões, etapa)`.

### Task 2: `PerfilIa.decidir` — a função pura do envio

**Files:**
- Modify: `app/services/ramon/perfil_ia.rb`
- Modify: `app/services/ramon/horario_comercial.rb` (novo `aberto?(momento)`)
- Test: `spec/services/ramon/perfil_ia_spec.rb`, `spec/services/ramon/horario_comercial_spec.rb`

**Interfaces:**
- Consumes: Task 1.
- Produces: `Ramon::PerfilIa.decidir(perfil, etapa:, tools_usadas:, logistica:, handoff:, falhou:, fora_do_horario:)
  -> [Symbol, String]` (`:envia | :rascunho`, motivo). `Ramon::HorarioComercial.aberto?(momento) -> Boolean` (dia
  útil e dentro de `JANELAS`, fuso `TIME_ZONE`).

- [ ] **Step 1: Escrever o spec (tabela de combinação da spec)**

```ruby
describe '.decidir' do
  def d(perfil, **opts)
    described_class.decidir(perfil, **{ etapa: etapa['fase-novo'], tools_usadas: [], logistica: nil, handoff: false,
                                        falhou: false, fora_do_horario: false }.merge(opts))
  end
  let(:equilibrada) { gravar('padrao' => { 'base' => 'equilibrada' }) && described_class.de(conversa) }
  let(:inicial) { described_class.de(conversa) }

  it 'antes do Marcador sai; Tool de texto em rascunho segura a resposta toda' do
    expect(d(equilibrada)).to eq([:envia, 'antes_do_marcador'])
    expect(d(equilibrada, tools_usadas: ['simular_honorario'])).to eq([:rascunho, 'acao:citar_honorario'])
    expect(d(equilibrada, tools_usadas: ['mover_etapa'])).to eq([:envia, 'antes_do_marcador'])
  end

  it 'depois do Marcador: só logística, só com logistica sozinha, e Tool de texto é teto' do
    depois = etapa['fase-negociacao']
    expect(d(equilibrada, etapa: depois, logistica: true)).to eq([:envia, 'logistica'])
    expect(d(equilibrada, etapa: depois, logistica: nil)).to eq([:rascunho, 'depois_do_marcador'])
    expect(d(equilibrada, etapa: depois, logistica: true, tools_usadas: ['solicitar_documento']))
      .to eq([:rascunho, 'acao:pedir_documentos'])
  end

  it 'INICIAL = piloto limitado de hoje' do
    expect(d(inicial, logistica: true)).to eq([:envia, 'logistica'])
    expect(d(inicial, logistica: false)).to eq([:rascunho, 'depois_do_marcador'])
    expect(d(inicial, handoff: true, falhou: true)).to eq([:envia, 'handoff'])
    expect(d(inicial, logistica: true, fora_do_horario: true)).to eq([:envia, 'logistica'])
  end

  it 'pausa rascunho, Fechado, fora do horário em rascunho e falha de Tool viram rascunho' do
    conversa.update!(custom_attributes: { 'ia_pausa' => 'rascunho' })
    expect(d(described_class.de(conversa), handoff: true)).to eq([:rascunho, 'pausa'])
    conversa.update!(custom_attributes: {})
    expect(d(equilibrada, etapa: account.lead_stages.find_by(is_won: true))).to eq([:rascunho, 'fechado'])
    gravar('padrao' => { 'base' => 'cautelosa', 'marcador' => '_fim' })
    expect(d(described_class.de(conversa), fora_do_horario: true)).to eq([:rascunho, 'fora_do_horario'])
    expect(d(equilibrada, falhou: true)).to eq([:rascunho, 'ferramenta_falhou'])
  end
end
```

  Mais, em `horario_comercial_spec.rb`: `aberto?` verdadeiro numa terça 10h SP, falso às 12h30, falso num sábado 10h.

- [ ] **Step 2: Ver falhar no CI** (`undefined method 'decidir'`).
- [ ] **Step 3: Implementar `decidir`** — a ordem é a decisão:

```ruby
# pausa rascunho → Fechado → fora do horário (permissão r) → handoff (sai se logistica_sai?) → falhou →
# antes do Marcador: alguma Tool de texto com permissão r → rascunho, senão envia →
# depois do Marcador: alguma Tool de texto → rascunho (teto); logistica s e logistica == true → envia; senão rascunho
```
  A Etapa avaliada é o `etapa:` recebido (o job passa a do início do turno), não a de agora.

- [ ] **Step 4: Ver passar no CI.**
- [ ] **Step 5: Commit** — `feat(ia): PerfilIa.decidir + HorarioComercial.aberto?`.

### Task 3: `ResponseBuilderJob`, atraso e Tools bloqueadas pelo perfil

**Files:**
- Modify: `enterprise/app/jobs/captain/conversation/response_builder_job.rb`
- Modify: `enterprise/app/services/captain/assistant/agent_runner_service.rb`
- Modify: `enterprise/app/models/concerns/agentable.rb`, `enterprise/app/models/captain/scenario.rb`,
  `enterprise/app/models/captain/assistant.rb` (comentário da linha 39)
- Modify: `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb`
- Modify: `app/services/ramon/rascunho_carimbo.rb`
- Test: `spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb`,
  `spec/enterprise/services/enterprise/message_templates/hook_execution_service_spec.rb`,
  `spec/enterprise/services/captain/assistant/agent_runner_service_spec.rb`, `spec/services/ramon/rascunho_carimbo_spec.rb`

**Interfaces:**
- Consumes: `PerfilIa.de`, `#estado`, `#logistica_sai?`, `#tools_bloqueadas`, `PerfilIa.decidir`,
  `HorarioComercial.aberto?`.
- Produces:
  - `response['tools_usadas'] -> Array<String>` (ids do catálogo das Tools que rodaram no turno), montado no
    `AgentRunnerService` pelo `on_tool_complete` já existente, guardado em `context[:state][:ramon_tools_usadas]`.
  - `Concerns::Agentable#agent(sem_tools: [])`; `Captain::Scenario#agent_tools` deixa de fora os ids de `sem_tools`.
  - Carimbo da mensagem enviada: `content_attributes['ramon_piloto'] = { 'perfil' => nome, 'alvo' => alvo, 'etapa' =>
    chave_da_etapa, 'handoff' => Boolean, 'em' => iso8601 }` (era `{ 'modo', 'em' }`).
  - Nota-rascunho: `content_attributes['ramon_ia_rascunho'] = { 'alvo', 'etapa', 'motivo', 'handoff' }`.
  - `ramon_rascunho_ia` (carimbo da resposta humana) ganha `'alvo'` e `'etapa'` copiados da nota.

- [ ] **Step 1: Escrever os specs que falham.** Trocar todo `custom_attributes 'copiloto_modo' => 'piloto_total'` dos
  specs existentes por um perfil gravado em `account.settings` (helper local `perfil!(cfg)`). Casos novos:
  - `ia_pausa = 'pausada'` → job sai sem chamar o LLM (`expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)`).
  - Lead em Perdido → mesmo comportamento.
  - Equilibrada, lead em Qualificação, resposta sem Tool → mensagem pública com `ramon_piloto` `{'perfil' =>
    'Equilibrada', 'etapa' => 'fase-qualificacao'}`.
  - Mesma, com `response['tools_usadas'] = ['simular_honorario']` → nota privada `RASCUNHO…` com
    `ramon_ia_rascunho['motivo'] == 'acao:citar_honorario'`.
  - **Turno que cruza o Marcador:** lead em Reunião agendada (antes do Marcador da Equilibrada); durante o
    `generate_response` (stub) o lead vai para Reunião realizada → a resposta ainda sai pública.
  - INICIAL + `PilotoLogisticaService.logistica?` falso → rascunho; o classificador **não** é chamado quando
    `estado == :sozinha` (custo).
  - `hook_execution_service`: atraso `RESPOSTA_IA_ATRASO` só quando `PerfilIa.de(conversation).logistica_sai?`; aviso
    de cota estourada (`agendar_aviso_de_handoff`) com a mesma condição.
  - `agent_runner_service`: com `marcar_reuniao = 'n'` no perfil, as Tools das skills não incluem `agendar_reuniao`
    nem `horarios_livres`; `response['tools_usadas']` traz o id da Tool que rodou.
  - `rascunho_carimbo`: resposta humana a uma nota com `ramon_ia_rascunho` `{'alvo' => 'padrao', 'etapa' =>
    'fase-novo'}` grava os dois em `ramon_rascunho_ia`.
- [ ] **Step 2: Ver falhar no CI.**
- [ ] **Step 3: Implementar.**
  - Job, `perform`: `@perfil = Ramon::PerfilIa.de(@conversation)`; `return if @perfil.estado == :pausada`.
  - `memoizar_logistica`: só quando `@perfil.estado != :sozinha && @perfil.permissao('logistica') == :sozinha`.
  - `create_outgoing_message`: `decisao, motivo = Ramon::PerfilIa.decidir(@perfil, etapa: @perfil.etapa,
    tools_usadas: @response&.dig('tools_usadas') || [], logistica: @logistica_ok, handoff: @enviando_handoff == true,
    falhou: @response&.dig('ferramenta_falhou') == true, fora_do_horario: !Ramon::HorarioComercial.aberto?(Time.current))`.
    O carimbo passa a vir de `@perfil` (método privado no job; `Ramon::Roteiro::Opcoes.atributos` recebe o hash novo).
  - `create_draft_note(conteudo, motivo)` grava `ramon_ia_rascunho`.
  - Runner: `bloqueadas = @conversation ? Ramon::PerfilIa.de(@conversation).tools_bloqueadas : []` em
    `build_and_wire_agents`, passado a `@assistant.agent(sem_tools:)` e a cada `scenario.agent(sem_tools:)`.
  - Hook: `atraso_resposta_ia` e `perform_handoff` trocam `CopilotoModo.piloto?(…)` por
    `Ramon::PerfilIa.de(conversation).logistica_sai?`.
- [ ] **Step 4: Ver passar no CI.**
- [ ] **Step 5: Commit** — `feat(ia): job da resposta decide pelo Perfil da IA`.

### Task 4: Roteiro, reunião, contrato e desfazer pelo perfil; Pausa no lugar do modo

**Files:**
- Modify: `app/services/ramon/perfil_ia.rb` (Pausa)
- Modify: `app/services/ramon/roteiro/efeitos.rb`, `app/services/ramon/roteiro/registro.rb:126`,
  `app/services/ramon/roteiro/teste.rb`
- Modify: `enterprise/lib/captain/tools/agendar_reuniao_tool.rb`, `enterprise/lib/captain/tools/preparar_contrato_zapsign_tool.rb`
  (só a `description`: tirar "modo sozinha até o contrato")
- Modify: `app/services/ramon/contrato_automatico.rb`, `app/services/ramon/reuniao_agendamento.rb:50-70`
- Modify: `app/models/funil_acao.rb`, `app/services/ramon/funil_observador/aplicar.rb:66-70`
- Test: `spec/services/ramon/roteiro_spec.rb`, `spec/services/ramon/roteiro_reabrir_spec.rb`,
  `spec/enterprise/lib/captain/tools/agendar_reuniao_tool_spec.rb`, `spec/services/ramon/contrato_automatico_spec.rb`,
  `spec/services/ramon/reuniao_agendamento_spec.rb`, `spec/models/funil_acao_spec.rb`,
  `spec/services/ramon/funil_observador/aplicar_spec.rb`, `spec/services/ramon/perfil_ia_spec.rb`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `PerfilIa.pausar(conversa, valor)` — `valor` em `PAUSAS` ou `nil`; guarda a pausa de antes em
    `custom_attributes['ia_pausa_antes_roteiro']` só se ainda não houver (mesma regra do `MODO_ANTES` de hoje; guarda
    `nil` quando não havia pausa).
  - `PerfilIa.restaurar_pausa(conversa) -> Boolean | nil` — devolve a guardada (ou tira `ia_pausa`) e apaga a chave;
    `nil` se não havia nada guardado.
  - `Efeitos.desqualificacao(lead) -> :nada | :perder | :sugerir | :equipe`.
  - `FunilAcao#desfazer['pausa']` no lugar de `desfazer['modo']`.

- [ ] **Step 1: Escrever os specs que falham** (reescrever os casos de modo dos specs listados). Casos que a spec pede:
  - `mover_etapa` `s` com a Etapa antes do Marcador → move; `r` → Sugestão `move_stage`; `n` → nem move nem sugere.
  - `desqualificar` `s` → Perdido + `ia_pausa = 'pausada'` + etiqueta; `r` → Sugestão `perdido`; `n` → `humano`
    (bot_handoff + `ia_pausa = 'rascunho'` + aviso) e o Registro marca `aguarda_equipe`.
  - Saída "humano" do roteiro → `ia_pausa = 'rascunho'`; reabrir → volta a pausa de antes, tira a etiqueta e devolve a
    conversa ao robô se a pausa restaurada não for `'pausada'`.
  - `agendar_reuniao`: marca de verdade só com `direto?('marcar_reuniao')` + Closer com Google; senão Sugestão.
  - `ContratoAutomatico.preparar`: roda só com `direto?('contrato_zapsign')`; faltou dado → `{ falta: }` (o aviso e a
    Pausa do "não saiu" são da Task 5, em `CopilotoLimite.falhou`).
  - `ReuniaoAgendamento.enviar_confirmacao` / `envia_sozinha?`: a condição `piloto?` vira `logistica_sai?` do perfil
    da conversa.
  - `FunilAcao` desfazer de um Perdido do observador devolve a `ia_pausa` de antes.
  - `Teste.de_params` aceita `roteiro['perfil']` (cfg, passa por `normalizar`); sem ele, usa o cfg efetivo da tese
    (ou do padrão). `com_lead` grava em `lead.perfil_ia_simulado`.
- [ ] **Step 2: Ver falhar no CI.**
- [ ] **Step 3: Implementar.** Trocas diretas: `direto?(lead)` some de `Efeitos`; `mover` usa
  `PerfilIa.de(lead).direto?('mover_etapa')` (e `permissao == :nunca` → `return`); `calar` = etiqueta +
  `pausar(conversa, 'pausada')`; `humano` = `pausar(conversa, 'rascunho')`; `devolver_ao_robo` lê `ia_pausa`.
  `FunilAcao#desfazer_limite` sai (não há modo a devolver: o Marcador recalcula a cada turno); `restaurar_modo` vira
  `restaurar_pausa` lendo `desfazer['pausa']` (linha antiga com `'modo'` é ignorada). `aplicar.rb#desfazer_perdido`
  grava `'pausa' => conversa.custom_attributes['ia_pausa']`.
- [ ] **Step 4: Ver passar no CI.**
- [ ] **Step 5: Commit** — `feat(ia): roteiro, reunião e contrato pelo Perfil da IA; Pausa da conversa`.

### Task 5: `CopilotoLimite` vira o aviso de cruzar o Marcador; `CopilotoModo` sai

**Files:**
- Modify: `app/services/ramon/copiloto_limite.rb`, `app/models/lead.rb:65-66`, `app/models/concerns/lead_roteiro.rb`
  (saem `copiloto_modo`/`copiloto_modo_simulado`), `app/services/ramon/contrato_automatico.rb#parar` (chama `falhou`)
- Modify: `app/listeners/ramon_lead_listener.rb:12-13` (sai `carimbar_padrao`)
- Modify: `app/models/inbox.rb:58-59`, `app/controllers/api/v1/accounts/inboxes_controller.rb:163`
- Modify: `app/views/layouts/vueapp.html.erb:60` (sai `ramonCopilotoModoDefault`), `.env.example:297`
- Modify: `enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb` (`cartao` sem `modo_padrao` e
  sem `conversas_por_modo`)
- Modify: `app/javascript/dashboard/routes/dashboard/captain/assistants/Index.vue` (sai o bloco "Modo das conversas")
- Delete: `app/services/ramon/copiloto_modo.rb`, `spec/services/ramon/copiloto_modo_spec.rb`
- Test: `spec/services/ramon/copiloto_limite_spec.rb` (reescrito), `spec/listeners/ramon_lead_listener_spec.rb`,
  `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb`,
  `spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb`, `spec/models/lead_roteiro_spec.rb`

**Interfaces:**
- Consumes: Tasks 1 e 4.
- Produces: `Ramon::CopilotoLimite.verificar(lead) -> String | nil` (chave do Marcador avisado) e
  `Ramon::CopilotoLimite.falhou(lead, motivo)` (usado pelo `ContratoAutomatico`). Carimbo
  `conversation.custom_attributes['copiloto_limite'] = { 'limite' => 'marcador' | 'contrato_falhou', 'marcador' =>
  m, 'etapa' => chave, 'motivo' => …, 'em' => iso8601 }` (a `bi_roteiro` lê `limite`, `em`, `motivo`).

- [ ] **Step 1: Specs que falham.**
  - Lead com conversa vai de Reunião agendada para Reunião realizada na Equilibrada → carimbo `'limite' =>
    'marcador'`, `'marcador' => 'fase-reuniao-agendada'` e `Ramon::AvisoDaIa.avisar` uma vez; outra mudança de etapa
    depois do Marcador não avisa de novo; mudar o Marcador na conta e cruzar de novo avisa.
  - Marcador `'_inicio'` nunca avisa (nada saía sozinho).
  - A conversa **não** muda: nem `ia_pausa`, nem nada além do carimbo.
  - `falhou` grava `'limite' => 'contrato_falhou'`, `ia_pausa = 'rascunho'` (é o que o modo fazia ao encerrar;
    *chamada do plano*) e avisa; `ContratoAutomatico` sem modelo de contrato chama `falhou`.
  - Listener: conversa nova não ganha atributo nenhum de modo.
  - Inbox: `ramon_copiloto_modo` não é mais aceito pela API (o parâmetro é ignorado); a coluna fica até a Fase 6.
  - Assistentes `stats`: cartão sem `modo_padrao`/`conversas_por_modo`.
- [ ] **Step 2: Ver falhar no CI.**
- [ ] **Step 3: Implementar.** Callback do Lead: `after_update_commit -> { Ramon::CopilotoLimite.verificar(self) },
  if: -> { saved_change_to_lead_stage_id? || saved_change_to_conversation_id? }` (sai `contrato_mudou?`). Aviso:
  `"IA passou do marcador com #{lead.name} - daqui pra frente ela escreve rascunho"` (texto interno da equipe, mesmo
  tom dos avisos de hoje). `grep -rn "CopilotoModo\|copiloto_modo" app enterprise lib` só pode sobrar em
  `db/` e no front da Fase 4.
- [ ] **Step 4: Ver passar no CI.**
- [ ] **Step 5: Commit** — `refactor(ia): CopilotoLimite avisa o Marcador; sai o CopilotoModo`.

### Task 6: Migração dos modos para perfis (rake idempotente)

**Files:**
- Create: `app/services/ramon/perfil_ia/migracao.rb`, `lib/tasks/ramon_perfil_ia.rake`
- Test: `spec/services/ramon/perfil_ia/migracao_spec.rb`

**Interfaces:**
- Consumes: `PerfilIa::INICIAL`, `PRONTOS`, `PAUSA`.
- Produces: `Ramon::PerfilIa::Migracao.rodar(account) -> Hash` com `padrao` (`'gravado' | 'mantido'`), `caixas`,
  `teses`, `descartadas` (`[{ caixa:, modo:, motivo: }]`), `conversas_pausadas`, `conversas_rascunho`. Rake
  `ramon:perfil_ia:migrar` roda em todas as contas e imprime o hash.

- [ ] **Step 1: Spec que falha** — com a tabela de Migração da spec:
  - `ramon_copiloto_modo` → cfg: `'rascunho'` → `INICIAL` com `logistica 'r'`; `'piloto_limitado'` → `INICIAL`;
    `'piloto_ate_qualificacao'` → `{ 'base' => 'cautelosa' }`; `'piloto_ate_reuniao'` → `{ 'base' => 'equilibrada' }`;
    `'piloto_ate_contrato'` / `'piloto_total'` → `{ 'base' => 'acelerada' }`; `'manual'` ou vazio → nada.
  - Caixa sem tese → `caixas[id]`. Caixa com `ramon_thesis_id` → `teses[tese_id]` se a tese ainda não tem cfg; senão
    entra em `descartadas`.
  - Conversa `copiloto_modo = 'manual'` → `ia_pausa = 'pausada'`; `'rascunho'` **com** a chave
    `copiloto_modo_antes_roteiro` → `ia_pausa = 'rascunho'`; as duas chaves antigas saem de todas as conversas.
  - Rodar duas vezes dá o mesmo `settings`; conta com `ia_atendimento.padrao` já gravado fica com `padrao: 'mantido'`.
- [ ] **Step 2: Ver falhar no CI.**
- [ ] **Step 3: Implementar.** Conversas em lote: `account.conversations.where("custom_attributes ? 'copiloto_modo'")`
  com `find_each`; um `update!` por conversa (dispara o `audited`, desejado). Lê a coluna com
  `inbox.read_attribute(:ramon_copiloto_modo)`.
- [ ] **Step 4: Ver passar no CI.**
- [ ] **Step 5: Commit** — `feat(ia): migração dos modos do copiloto para o Perfil da IA`. Abrir o PR 1.

---

## Fase 2 — Gatilhos de equipe no prompt (PR 2, gate de texto)

### Task 7: Gatilhos montados por conversa

**Files:**
- Modify: `app/services/ramon/perfil_ia.rb` (`GATILHOS` vira hash com nome e texto)
- Modify: `enterprise/app/services/captain/assistant/agent_runner_service.rb#build_state`,
  `enterprise/app/models/concerns/agentable.rb#agent_instructions`
- Modify: `db/seeds/ramon/inteligencia/assistentes.yml` (Atendimento: as linhas que viram gatilho saem de
  `response_guidelines`)
- Test: `spec/services/ramon/perfil_ia_spec.rb`, `spec/enterprise/models/captain/assistant_spec.rb` (ou o spec de
  `agent_instructions` que já existir)

**Interfaces:**
- Produces: `GATILHOS = { chave => { 'nome' => String, 'texto' => String | nil } }`; `#textos_dos_gatilhos(etapa =
  @etapa) -> Array<String>` (só os ligados naquela Etapa e com texto); `state[:ramon_gatilhos]`.

Textos (redação de hoje; a 1ª linha atual é dividida em duas — **o Eduardo aprova antes do merge**):

| chave | nome na tela | texto para o prompt |
|---|---|---|
| `pediu_pessoa` | Pediu para falar com uma pessoa | "Se o lead pedir para falar com uma pessoa ou com um advogado, passe para humano." |
| `juridica` | Dúvida ou decisão jurídica | "Sempre que uma dúvida exigir decisão jurídica sobre o caso concreto, passe para humano." |
| `outra_area` | Outra área do direito | a linha atual "Você atende a banca inteira (…) sem pedir detalhes desse outro assunto." |
| `fora_do_tema` | Fora do tema da tese | a linha atual "Se o lead contar um caso ou pedir ajuda num assunto diferente da tese (…) responda pela FAQ." |
| `honorario_de_novo` | Perguntou o honorário de novo | a linha atual "Se o lead perguntar o valor do honorário pela segunda vez (…)" |
| `nao_le` | Não consegue ler ou escrever | a linha atual "Se o lead disser que não sabe ler (…)" |
| `irritado`, `tem_advogado`, `desconto`, `clausula` | Lead irritado · Já tem advogado · Pediu desconto · Quer mudar cláusula | `nil` (pendente de texto; a tela mostra "texto pendente" e não deixa ligar) |

O que sobra da 1ª linha atual fica nas diretrizes: "Se o lead disser que quer contratar, siga a skill Fechar contrato
(…). Nunca diga que está \"transferindo\": diga só que alguém da equipe continua a conversa por aqui."

- [ ] **Step 1: Spec que falha** — perfil Cautelosa em Qualificação → `textos_dos_gatilhos` tem os 6 textos, na ordem
  de `GATILHOS`; Acelerada → não tem `honorario_de_novo` nem `nao_le`; `cfg['gatilhos']['fase-qualificacao'] =
  ['juridica']` → só esse; `agent_instructions` com `state[:ramon_gatilhos]` inclui cada texto nas diretrizes.
- [ ] **Step 2: Ver falhar no CI.**
- [ ] **Step 3: Implementar.** `gatilhos(etapa) = cfg.dig('gatilhos', chave_da_etapa) || PRONTOS[base]['gatilhos']`.
  Em `agent_instructions`, somar `state[:ramon_gatilhos]` a `response_guidelines` do `enhanced_context`.
- [ ] **Step 4: Ver passar no CI.** `texto_final` (Assistentes → "texto final") continua mostrando o prompt sem
  conversa — sem gatilhos; anotar no doc de entrega.
- [ ] **Step 5: Gate (FECHADO — Eduardo aprovou a tabela em 17/10)** — commit
  `feat(ia): gatilhos de equipe por etapa no prompt`, PR 2, e o `rake ramon:inteligencia:seed` entra no deploy do pacote.

---

## Fase 3 — A tela "Como a IA atende" (PR 3)

### Task 8: API `ramon_ia_atendimento` (show/update)

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_ia_atendimento_controller.rb`, `app/services/ramon/perfil_ia/tela.rb`
- Modify: `config/routes.rb` (perto da linha 375: `resource :ramon_ia_atendimento, only: [:show, :update],
  controller: 'ramon_ia_atendimento'`), `app/services/ramon/perfil_ia.rb` (`gravar!`)
- Test: `spec/controllers/api/v1/accounts/ramon_ia_atendimento_controller_spec.rb`

**Interfaces:**
- Consumes: Tasks 1, 7.
- Produces:
  - `GET` → `{ prontos: PRONTOS, inicial: INICIAL, acoes: [{ chave, etapa, sem_nunca }], gatilhos: [{ chave, nome,
    pendente }], etapas: [{ chave, nome }], padrao: cfg, teses: [{ id, nome, cfg | null }], caixas: [{ id, nome, cfg |
    null }] }`. `acoes[].etapa` (onde a linha aparece): `fora_do_horario` → `fase-novo`; `pedir_documentos`,
    `desqualificar`, `mover_etapa`, `marcar_reuniao`, `citar_honorario` → `fase-qualificacao`; `logistica` →
    `fase-reuniao-agendada`; `contrato_zapsign` e `citar_honorario` → `fase-negociacao`. `caixas` = caixas da conta sem
    `ramon_thesis_id` e com `try(:captain_assistant)`.
  - `PATCH` com `{ padrao: cfg, teses: { id => cfg | null }, caixas: { id => cfg | null } }` (parcial; `null` = segue o
    padrão) → mesmo corpo do `GET`. Inválido → 422 `{ error: }`, nada gravado.
  - `Ramon::PerfilIa.gravar!(account, alvos)` — um `account.update!` só (uma linha de auditoria por save); levanta
    `ArgumentError` com o motivo.
- [ ] **Step 1: Spec que falha** — agente recebe 403 (`RamonIaPolicy#gerenciar?`); admin lê o corpo acima; `PATCH`
  com tese de outra conta, base `'xablau'`, permissão `'n'` em `logistica`, Marcador inexistente ou gatilho fora de
  `GATILHOS` → 422 e `settings` igual (gatilho pendente pode estar no cfg — os prontos o trazem —, só não entra no
  prompt); `PATCH` válido grava só os alvos enviados.
- [ ] **Step 2: Ver falhar no CI.**
- [ ] **Step 3: Implementar** (molde: `ramon_ia_uso_controller.rb`).
- [ ] **Step 4: Ver passar no CI.**
- [ ] **Step 5: Commit** — `feat(ia): API da tela Como a IA atende`.

### Task 9: Página, Trilha e limites (front)

**Files:**
- Create: `app/javascript/dashboard/api/ramonIaAtendimento.js`
- Create: `app/javascript/dashboard/routes/dashboard/ramon/helpers/perfilIa.js` + `specs/perfilIa.spec.js`
- Create: `app/javascript/dashboard/routes/dashboard/captain/pages/ComoIaAtende.vue` +
  `pages/comoIaAtende/ListaAlvos.vue`, `Trilha.vue`, `LimitesDaEtapa.vue` + `pages/specs/ComoIaAtende.spec.js`
- Modify: `captain/captain.routes.js` (rota `captain/como-a-ia-atende`, name `captain_como_ia_atende_index`,
  `meta: metaAdmin`, antes do catch-all), `components-next/sidebar/Sidebar.vue` (item logo depois de Visão geral, só
  admin como o IaUso), `i18n/locale/en/ramon.json` + `pt_BR/ramon.json` (`RAMON.COMO_IA.*`, `SIDEBAR.CAPTAIN_COMO_IA`)

**Interfaces:**
- Consumes: Task 8 (`GET`/`PATCH`).
- Produces (helper puro, espelho do Ruby): `efetivo(cfg, prontos, inicial) -> { base, marcador, permissoes, gatilhos }`,
  `ajustes(cfg, prontos) -> Number`, `estadoDaEtapa(chave, marcador, etapas) -> 'sozinha' | 'rascunho'`,
  `permissaoEfetiva(acao, etapa, cfg…) -> { valor, limitadoPeloMarcador }`, `frase(marcador, etapas, t) -> String`.
- [ ] **Step 1: Specs que falham** — `perfilIa.spec.js`: `ajustes` conta ação, Marcador e gatilho diferentes da base;
  `permissaoEfetiva('contrato_zapsign', 'fase-negociacao', …)` na Equilibrada dá `{ valor: 'rascunho',
  limitadoPeloMarcador: true }`. `ComoIaAtende.spec.js` (API mockada como em `UsoCusto.spec.js`): escolher Acelerada
  mostra o selo; mover o Marcador com ArrowRight muda a frase; clicar na Permissão alterna S→R→N e pula N em
  `logistica`; "Personalizar só esta" numa tese copia o padrão; "Salvar alterações" manda só os alvos mudados;
  contador de não salvas.
- [ ] **Step 2: Ver falhar** — `pnpm test ramon/helpers/specs/perfilIa.spec.js` (local se houver `node_modules`, senão CI).
- [ ] **Step 3: Implementar** seguindo o mockup aprovado (layout, cópia, interação). Detalhes que o mockup não tinha:
  linha "Confirmação da reunião: definida no fluxo Reuniões →" só leitura em Reunião agendada; linha de desconto
  travada "Nunca · regra do escritório" em Negociação; tooltip dos gatilhos "orientação à IA, não garantia"; gatilho
  pendente mostra "texto pendente" e não liga. Fechar a página com alterações não salvas pergunta antes.
- [ ] **Step 4: Ver passar** (mesmo comando) + `pnpm eslint` nos arquivos.
- [ ] **Step 5: Commit** — `feat(ia): tela Como a IA atende`. Abrir o PR 3.

---

## Fase 4 — Botão da conversa, carimbo e limpeza (PR 4)

### Task 10: Botão "IA: {perfil} · {etapa}" e Pausar no carimbo

**Files:**
- Create: `app/controllers/api/v1/accounts/ramon_ia_conversas_controller.rb` (rota `get
  'ramon_ia_conversas/:conversation_id'`), `ramon/components/conversation/IaDaConversa.vue` +
  `specs/IaDaConversa.spec.js`
- Modify: `components/widgets/conversation/ConversationHeader.vue:13,178`, `components-next/message/PilotoCarimbo.vue`
  + spec
- Delete: `ramon/components/conversation/CopilotoModoSelector.vue` + spec
- Test: `spec/controllers/api/v1/accounts/ramon_ia_conversas_controller_spec.rb`

**Interfaces:**
- Produces: `GET` → `{ perfil: nome, origem: 'tese' | 'caixa' | 'padrao', etapa: nome | null, pausa: null |
  'pausada' | 'rascunho', alvo: 'tese:3' | … }`; autorização = a conversa da conta que o usuário pode ver
  (`authorize conversation, :show?`).
- [ ] **Step 1: Specs que falham** — controller: agente sem acesso à caixa → 403/404; corpo certo para tese, caixa e
  padrão. `IaDaConversa.spec.js`: rótulo `IA: Equilibrada (da tese) · Qualificação`; "Pausar a IA nesta conversa"
  grava `ia_pausa: 'pausada'` (merge completo dos `custom_attributes`) e abre a conversa pendente; "Só rascunho" grava
  `'rascunho'`; "Voltar a seguir o perfil" tira a chave; "Ver na trilha" vai para `captain_como_ia_atende_index` com
  `?alvo=`; "Assumir" = atribuir a mim (action de atribuição que o cabeçalho já usa) + `ia_pausa: 'pausada'`.
  `PilotoCarimbo.spec.js`: mostra `ramon_piloto.perfil`, "Pausar" grava `ia_pausa: 'rascunho'`.
- [ ] **Step 2–4:** ver falhar, implementar, ver passar (CI + `pnpm eslint`). A tela (Task 9) lê `?alvo=` e abre o alvo.
- [ ] **Step 5: Commit** — `feat(ia): botão da IA na conversa`.

### Task 11: Limpeza das telas antigas

**Files:**
- Modify: `settings/inbox/Settings.vue` (sai o campo "Modo padrão da IA" e o envio de `ramon_copiloto_modo`; entra
  linha com link "Configurar em Como a IA atende"), `settings/inbox/AddAgents.vue:9,45-47`,
  `components-next/captain/pageComponents/inbox/ConnectInboxForm.vue` (sai `AVISO_RASCUNHO`) + spec,
  `captain/pages/VisaoGeral.vue` (sai o bloco `vg-piloto`; no servidor sai `piloto` e `META_PILOTO` de
  `app/controllers/api/v1/accounts/ramon_inteligencia_controller.rb` + o spec dele), `captain/assistants/playground/Index.vue` (sai o seletor
  de modo; o Testar ganha perfil na Task 13), `captain/pages/Inteligencia.story.vue`, i18n `en`/`pt_BR` (somem
  `RAMON.COPILOTO.MODOS.*`, `BTN`, `TITULO`, `CAPTAIN.INBOXES.FORM.AVISO_RASCUNHO`, `VISAO_GERAL.PILOTO.*`)
- Delete: `ramon/helpers/copilotoModo.js` + spec
- [ ] **Step 1:** `grep -rn "copilotoModo\|COPILOTO.MODOS\|AVISO_RASCUNHO\|ramon_copiloto_modo" app/javascript` → a
  lista é o checklist; os specs que quebram são ajustados para o novo texto.
- [ ] **Step 2:** remover/trocar; a "Tese padrão da caixa" fica.
- [ ] **Step 3:** `pnpm test` dos specs tocados + `pnpm eslint` + grep acima vazio.
- [ ] **Step 4: Commit** — `refactor(ia): uma tela só decide a autonomia da IA`. Abrir o PR 4.
- [ ] **Step 5: Pacote 1** — com os PRs 1–4 mergeados: deploy na VPS, `rake ramon:perfil_ia:migrar` (guardar a
  saída no doc de entrega), `rake ramon:inteligencia:seed` (se o PR 2 entrou), conferir que a caixa Teste ficou com o
  perfil esperado, doc de entrega com smoke em bloco (Seção A: tela; B: conversa e Pausa; C: cruzar o Marcador).

---

## Fase 5 — Limites gerais, números, Testar, histórico e avisos (PR 5)

### Task 12: Limites gerais do escritório

**Files:**
- Create: `app/services/ramon/ia_limites.rb`
- Modify: `app/services/ramon/horario_comercial.rb`, `app/services/ramon/agenda/disponibilidade.rb:73`,
  `app/services/ramon/painel_time_sdr.rb:42,53`, `enterprise/.../hook_execution_service.rb` (atraso),
  `app/services/ramon/fluxos/passos/ia.rb:120`, `app/services/ramon/ia_uso_resumo.rb:82`,
  `app/services/ramon/fluxos/retomada.rb`, `app/services/ramon/follow_up_draft_service.rb:6-7`, controller e tela da
  Task 8/9 (seção "Limites gerais" só no Padrão do escritório)
- Test: `spec/services/ramon/ia_limites_spec.rb` + os specs dos leitores

**Interfaces:**
- Produces: `Ramon::IaLimites.de(account) -> { horario: { 'dias' => [1..5], 'janelas' => [['08:30','12:00'],
  ['13:30','18:00']] }, atraso: 30..180, fluxo_ia_dia: Integer, retomadas_dia: 15, retomada_intervalo_dias: 5 }` (lê
  `settings['ia_limites']`; ausente = os valores de hoje; `fluxo_ia_dia` ausente = env `RAMON_FLUXO_IA_DIA`);
  `IaLimites.gravar!(account, hash)` valida (atraso máx ≤ 180 s, mín ≤ máx, janelas em ordem). `HorarioComercial`
  ganha `account` opcional em `minutos_entre`, `aberto?` e um `janelas(account)` que a `Disponibilidade` usa. O
  `GET`/`PATCH` da Task 8 ganham `limites` e o teto US$ (`Ramon::IaGastoAlerta::CHAVE_TETO`); agente @claude = só
  leitura `AgenteExecucao::TETO_DIA`.
- [ ] **Steps 1–5:** spec (valores padrão = os de hoje; atraso 200 s → 422; horário gravado muda `aberto?` e as
  janelas da Agenda), implementar, CI verde, commit `feat(ia): limites gerais do escritório editáveis`.

### Task 13: Números por etapa, "Passar pra Sozinha?" e Testar este perfil

**Files:**
- Create: `app/services/ramon/perfil_ia/numeros.rb`
- Modify: controller/tela das Tasks 8/9, `app/services/ramon/roteiro/teste.rb`,
  `enterprise/.../assistants_controller.rb#playground`, `captain/assistants/playground/Index.vue`
- Test: `spec/services/ramon/perfil_ia/numeros_spec.rb`, `spec/enterprise/controllers/api/v1/accounts/captain/assistants_controller_spec.rb`

**Interfaces:**
- Produces: `Ramon::PerfilIa::Numeros.de(account, alvo) -> { etapa_chave => { enviadas:, rascunhos: { igual:,
  editado:, descartado: }, chamou_equipe:, sugerir_sozinha: Boolean } }` (30 dias; lê os carimbos da Task 3:
  `ramon_piloto`, `ramon_ia_rascunho`, `ramon_rascunho_ia`; `chamou_equipe` = `handoff: true` em qualquer um). Regra
  da sugestão: Etapa em rascunho, revisados (`igual + editado + descartado`) ≥ `Numeros::MINIMO_REVISADOS = 20` (o
  `META_PILOTO` de hoje, que sai do controller da Visão geral na Task 11) e `igual / revisados ≥ 0.9`. Playground: `roteiro: { thesis_id, estado, perfil }`
  e a resposta ganha `decisao: { valor: 'envia' | 'rascunho', motivo }` vinda de `PerfilIa.decidir` com o perfil
  simulado, e `bloqueadas: [ids]`.
- [ ] **Steps 1–5:** spec (sem carimbo = "sem dados ainda"; 20 revisados com 19 iguais → `sugerir_sozinha`; o Testar
  com `citar_honorario 'r'` e `tools_usadas ['simular_honorario']` devolve `rascunho / acao:citar_honorario`); a tela
  mostra os números embaixo dos limites e o aviso com botão que vira ajuste; "Testar este perfil" abre o playground do
  assistente da caixa/tese com o cfg da tela (não salvo) e mostra a decisão debaixo de cada resposta. Commit
  `feat(ia): números por etapa e Testar este perfil`.

### Task 14: Histórico com desfazer e avisos de dependência

**Files:**
- Modify: `app/services/ramon/registro_acoes.rb` (`TIPOS['ia'] = %w[Account]` filtrando `audited_changes ?
  'settings'` com mudança em `ia_atendimento`/`ia_limites`), `app/javascript/.../helpers/registroAcoes.js` (frase
  "Eduardo mudou BPC/LOAS: marcar reunião rascunho → sozinha"), controller da Task 8 (`POST desfazer` com `audit_id`),
  tela da Task 9 (botão Histórico → Registro de ações filtrado; avisos âmbar)
- Create: `app/services/ramon/perfil_ia/avisos.rb`
- Test: `spec/services/ramon/registro_acoes_spec.rb`, `spec/services/ramon/perfil_ia/avisos_spec.rb`, specs do controller e do helper JS

**Interfaces:**
- Produces: `Ramon::PerfilIa::Avisos.de(account) -> { 'tese:3' => [{ acao:, tipo:, link: }] }` com os 5 avisos da spec
  (`zapsign_template_id` vazio; `honorario_na_tabela == false`; nenhum Closer com `GoogleAgendaConta`; roteiro sem
  saída Qualificado; caixa com perfil sem assistente). Desfazer: regrava o valor anterior **daquele alvo** a partir do
  `audited_changes['settings'][0]` da linha (vira outra linha de auditoria).
- [ ] **Steps 1–5:** spec (o Registro com tipo `ia` mostra só mudanças de perfil, não outras de `settings`; desfazer
  devolve só o alvo da linha; cada aviso aparece e some quando a causa some), implementar, CI verde, commit
  `feat(ia): histórico com desfazer e avisos na tela`. Abrir o PR 5; deploy = pacote 2; smoke em bloco (D: limites;
  E: números e Testar; F: histórico e avisos).

---

## Fase 6 — Tirar a coluna antiga (PR 6, depois do pacote 1 no ar)

### Task 15: Migração que remove `inboxes.ramon_copiloto_modo` e atualiza a `bi_roteiro`

**Files:**
- Create: `db/migrate/<timestamp>_remove_ramon_copiloto_modo_from_inboxes.rb`, `db/views/bi_roteiro_v04.sql` +
  migração do scenic (`update_view :bi_roteiro, version: 4`)
- Modify: `db/schema.rb` (regenerado via scratch DB na VPS), `spec/db/bi_roteiro_view_spec.rb`
- [ ] **Step 1:** spec da view: coluna `modo` passa a ser `c.custom_attributes ->> 'ia_pausa'`; o resto igual à v03.
- [ ] **Step 2:** migrações + `schema.rb` pela VPS (lição do fork).
- [ ] **Step 3:** CI verde; `grep -rn "ramon_copiloto_modo" app enterprise lib spec` vazio.
- [ ] **Step 4: Commit** — `chore(ia): remove a coluna do modo antigo`. PR 6; deploy com `db:migrate` à mão.
