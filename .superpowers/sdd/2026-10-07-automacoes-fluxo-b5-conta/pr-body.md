Automações em fluxo — B5-conta: as 7 rotinas da conta (resumo do dia, retrato do funil, fechamento do extrato, espelho do Painel, copiloto noturno, publicar peças no Instagram e avisos do Painel) ganham 7 fluxos de verdade num gatilho novo, **"Horário da conta"** — horário e dias editáveis (ou "a cada N minutos"), liga/desliga e push antes/depois. Cada rotina chama exatamente o mesmo código de hoje, com as mesmas travas (avisos só com PORTAL_AVISOS; Instagram só publica peça já agendada). Com as chaves desligadas (padrão) tudo segue pelo código como hoje; ligada e com o fluxo em modo normal, o fluxo faz e o código pula a conta — nunca os dois, nunca nenhum, nem na virada no meio do dia. Voltar é um comando, sem deploy. Na aba "Do sistema", as 5 regras de dado ganham o selo "regra fixa (fica no código)".

## Closes
- Spec `docs/superpowers/specs/2026-10-05-automacoes-em-fluxo-design.md` §8 (B5: rotinas da conta; revoga "resumo do dia fica no código"); notas novas em §19.

## How to test
1. Depois do deploy, criar os 7 fluxos (seção "Operação" abaixo): o runner mostra "modo sombra, ligado" e "Agora o CÓDIGO faz ...".
2. Inteligência > Automações > Meus fluxos: os 7 com o gatilho "Horário da conta" e o selo "em sombra"; abrir "Resumo do dia" > "Testar na conta..." > a trilha diz "faria: o resumo do dia".
3. Num fluxo novo, escolher "Horário da conta": "Quando roda" (uma vez por dia / a cada N minutos), dias, e a paleta só com os passos que rodam sem lead.
4. Aba "Do sistema": Histórico do lead, Documentos completos, Contrato limpo (e cancelado) e SDR automático com o selo "regra fixa".
5. Virar e conferir (passos 3 a 5 da Operação).

## What changed
- Gatilho `horario_conta` (`Ramon::Fluxos::HorarioConta`) no relógio de 1 minuto, com a vez reivindicada no banco; alvo = a conta no motor; ensaio na conta. Fora do comando, o fluxo só disputa a vez com o código quando tem a cadência do próprio código (por dia nas diárias; a cada 1 min no Publicar peças) — editar o ritmo em sombra não faz o código rodar mais vezes.
- Registro de rotinas por plano (`Ramon::Fluxos::Rotinas` + `rotinas/conta.rb`); os 7 jobs com `perform(account_id = nil)`; 7 desenhos em `db/seeds/ramon/fluxos/migrados/`; front com `rotinas/conta.js` e telas do Horário da conta.
- Selo `"fixa": true` nas 5 regras de dado da aba Do sistema.
- Envs `RAMON_FLUXO_ROTINAS`, `RAMON_FLUXO_PUBLICAR_PECAS`, `RAMON_FLUXO_AVISOS_PAINEL` (desligadas por padrão). Sem migração; o cron não muda.
- Só os 7 fluxos migrados não ensaiam sozinhos em sombra. Espelho, copiloto e Instagram vão para a fila (o push "depois" sai quando entram na fila).

## Operação depois do deploy
Conta da banca = **2**; console = `docker exec intranet-ramon-chatwoot-web-1 bundle exec rake "<task>"` / `... rails runner '<ruby>'`. Deploy sem migração. **Junto com o deploy**, acrescentar ao `chatwoot.env` em `/opt/intranet-ramon`: `RAMON_FLUXO_ROTINAS=on`, `RAMON_FLUXO_PUBLICAR_PECAS=on`, `RAMON_FLUXO_AVISOS_PAINEL=on` (seguro: sem os fluxos em modo normal, o código segue fazendo tudo). Recriar web **e** worker.

**Não criar os fluxos no minuto exato de uma rotina (00:05, 00:20, 00:30, 05:00, 08:00).**

1. **Criar os 7 fluxos (código ainda no comando).**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
Ramon::Fluxos::Rotinas::Conta::JOBS.each_key { |k| Ramon::Fluxos::Migracao.semear(a, k); puts Ramon::Fluxos::Migracao.descrever(a, k) }'
```
Esperado: 7 x "modo sombra, ligado" + "Agora o CÓDIGO faz ...". Rodar de novo não duplica. Criados depois do horário de hoje, só começam amanhã.

2. **Conferir na tela.** Meus fluxos: 7 com "Horário da conta" e selo "em sombra". "Resumo do dia" > Testar na conta > "faria: o resumo do dia". "Avisos do Painel do Cliente" > Testar: "avisos do Painel desligados ... nada enviado". Aba Do sistema: 5 com "regra fixa".

3. **Virar (os 7 juntos).**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
Ramon::Fluxos::Rotinas::Conta::JOBS.each_key { |k| Ramon::Fluxos::Migracao.mudar_modo!(a, k, "normal"); puts Ramon::Fluxos::Migracao.descrever(a, k) }'
```
Esperado: 7 x "Agora os FLUXOS fazem ...". (Uma só: `rake "ramon:fluxos:migracao:modo[resumo_do_dia,2,normal]"`.)

4. **Teste ao vivo de hoje.**
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
%w[resumo_do_dia retrato_funil].each { |k| Ramon::Fluxos::Migracao.fluxo(a, k).update_columns(created_at: 2.days.ago, ultimo_disparo_em: nil) }
puts "ok — em até 1 minuto o relógio roda os 2"'
```
Esperar 2 minutos e rodar o conferidor:
```
docker exec intranet-ramon-chatwoot-web-1 bundle exec rails runner '
a = Account.find(2)
Ramon::Fluxos::Rotinas::Conta::JOBS.each_key do |k|
  f = Ramon::Fluxos::Migracao.fluxo(a, k)
  e = f.execucoes.where(ensaio: false).order(:id).last
  puts "#{k}: #{f.modo} · #{e ? e.created_at.in_time_zone("America/Sao_Paulo").strftime("%d/%m %H:%M") : "nenhuma"} #{e&.status} — #{e&.trilha&.last&.dig("resumo")}"
end'
```
Esperado: `resumo_do_dia: normal · <hoje HH:MM> concluida — fez: o resumo do dia` e `retrato_funil: ... fez: o retrato do funil`; push "Ramon Hub · seu dia" (se o dia tem algo) e e-mail de gestão. Os outros: "nenhuma".

5. **Amanhã, depois das 08:05:** rodar o conferidor de novo. Esperado: `retrato_funil` 00:05, `fechamento_extrato` 00:20 (fora do 3º dia útil o job não faz nada, como hoje), `espelho_painel` 00:30 ("pôs na fila"), `copiloto_noturno` 05:00 ("pôs na fila"), `resumo_do_dia` 08:00, `avisos_painel` 08:00 ("desligados ... nada enviado"); `publicar_pecas` só depois da próxima peça agendada (ter/qua/qui 12h), com a peça publicada **uma vez**. Conferir **um** push "seu dia" às 8h e o Cockpit com as sugestões da madrugada uma vez só.

6. **Rollback (sem deploy, cada rotina independente).** `rake "ramon:fluxos:migracao:modo[<rotina>,2,sombra]"` volta o código ao comando (os 7: o runner do passo 3 com `"sombra"`). Também seguro: desligar o fluxo na tela ou tirar a env e recriar. A vez de hoje que o fluxo já pegou não é refeita pelo código (e vice-versa).

7. **Depois (outro PR).** Com 2 semanas em normal sem incidente: tirar 6 entradas do `config/schedule.yml` (todas menos `Ramon::PortalSyncJob`, que fica: é o cron dele que expurga os logs de acesso do Painel após 6 meses, Marco Civil, via `PortalAcesso.expurgar!`; ou vira job de expurgo próprio) e o ramo "cron" de `Rotinas::Conta.cada_conta`, os JSON `sistema/<rotina>.json` e as linhas `origem: sistema` deles, e as 3 envs.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Q7cdLj5F9nZkRyjQT3uBrR
