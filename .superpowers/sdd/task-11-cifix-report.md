# Task 11 — CI Fix: A1 Lint/Test Failures

## Context

Branch `feat/ramon-hub-a1-card-drawer`. Backend specs (16 shards) were passing; three
CI jobs failing (lint-backend/rubocop, lint-frontend/eslint, frontend-tests/vitest),
all due to A1 files. Fixed in one commit. rubocop/eslint/vitest are CI-deferred —
no local runner available (no Ruby/PG/Docker, pnpm not installed).

---

## A) rubocop — 5 offenses fixed

| # | File | Offense | Fix |
|---|------|---------|-----|
| 1 | `app/models/lead.rb:17` | `Metrics/CyclomaticComplexity [8/7]` on `push_event_data` | Added inline `# rubocop:disable Metrics/CyclomaticComplexity` on def line |
| 2 | `spec/controllers/api/v1/accounts/leads_controller_spec.rb:35` | `RSpec/MultipleExpectations [9/7]` | Added `:aggregate_failures` metadata to the example |
| 3 | `spec/models/lead_spec.rb:35` | `RSpec/DescribedClass` | `Lead.column_names` → `described_class.column_names` |
| 4 | `spec/models/lead_stage_spec.rb:22` | `RSpec/DescribedClass` | `LeadStage.column_names` → `described_class.column_names` |
| 5 | `spec/services/leads/seed_default_config_service_spec.rb:45` | `Rails/SkipsModelValidations` on `update_column` | `update_column(:color, nil)` → `update!(color: nil)` (safe — no validation on color) |

---

## B) eslint — 6 errors fixed

Rule `vue/custom-event-name-casing: ['error','camelCase']` requires camelCase emit names.
Rule `vue/v-on-event-hyphenation` wants kebab template listeners — so **listeners stay kebab, only emitted/declared names go camelCase**.

### Event name rename: `open-lead` → `openLead`

| File | Change |
|------|--------|
| `LeadCard.vue` | `defineEmits` `'open-lead'` → `'openLead'`; `emit('open-lead', lead)` → `emit('openLead', lead)` |
| `KanbanColumn.vue` | `defineEmits` `'open-lead'` → `'openLead'`; inner emit in template `emit('open-lead', lead)` → `emit('openLead', lead)` (listener `@open-lead=` kept kebab) |
| `KanbanBoard.vue` | No change — does not emit `open-lead`; absorbs it via `@open-lead="onOpenLead"` (listener stays kebab) |

### `vue/no-useless-v-bind` — 4 occurrences in `LeadDrawer.vue`

`<option :value="''">—</option>` → `<option value="">—</option>` in benefit, priority, sdr and closer selects (4 placeholder options). Stage select has no empty placeholder; `:value="lead.xxx_id"` bindings untouched.

---

## C) vitest — KanbanColumn re-emit test fixed

`specs/KanbanColumn.spec.js`: under `shallowMount`, `vuedraggable` is stubbed and does not render its `#item` slot → `findComponent(LeadCard)` returned nothing → `.vm` threw.

Fix: changed only the re-emit test to use `mount` (full render so Draggable renders the slot); added `mount` to the import; updated event name to `openLead`. The 4 drag tests remain on `shallowMount` unchanged.

Also updated event references in sibling specs:
- `specs/LeadCard.spec.js`: `emitted('open-lead')` → `emitted('openLead')` (2 occurrences)
- `specs/KanbanBoard.spec.js`: `.vm.$emit('open-lead', ...)` → `.vm.$emit('openLead', ...)`

---

## Prettier

All 7 touched `.vue`/`.js` files passed `npx prettier@3.3.3 --write` unchanged (already formatted).

---

## git grep open-lead result (post-fix)

```
app/javascript/.../kanban/KanbanBoard.vue:50:        @open-lead="onOpenLead"
app/javascript/.../kanban/KanbanColumn.vue:56:          @open-lead="lead => emit('openLead', lead)"
app/javascript/.../kanban/specs/KanbanBoard.spec.js:39:  it('seleciona o lead ao receber open-lead de uma coluna', () => {
app/javascript/.../kanban/specs/LeadCard.spec.js:36:  it('emite open-lead ao clicar no corpo', async () => {
```

Only template listeners (`@open-lead=`) and human-readable test description strings remain.
No `emit('open-lead'`, no `'open-lead'` in `defineEmits`, no `emitted('open-lead')` or `$emit('open-lead'` in specs.

---

## Deferred verification

rubocop, eslint, vitest all verified on next CI run. Expected: all 3 jobs green.
