# Cria/atualiza as 5 macros "Claude · …" do agente do hub (spec §2).
# Uso na VPS: bundle exec rails runner docs/agente_hub_macros.rb
# Envs: ACCOUNT_ID (default 2), EDUARDO_EMAIL (obrigatório).
ACCOUNT_ID = (ENV['ACCOUNT_ID'] || 2).to_i
EMAIL = ENV.fetch('EDUARDO_EMAIL')

account = Account.find(ACCOUNT_ID)
user = account.users.find_by!(email: EMAIL)

MACROS = {
  'Claude · Dossiê pro jurídico' =>
    '@claude monta o dossiê de passagem deste lead pro jurídico (tese do lead), com análise, riscos, documentos que faltam e ' +
    'próximo passo; salva no Drive e cria a tarefa no ADVBOX pro responsável.',
  'Claude · Análise de andamentos' =>
    '@claude lê os últimos andamentos e publicações do(s) processo(s) deste cliente no ADVBOX e me diz se há prazo ou providência pendente.',
  'Claude · Próximo passo' =>
    '@claude com base na conversa e no ADVBOX, qual o próximo passo com este lead? Seja objetivo (3 linhas).',
  'Claude · Minuta com dados do ADVBOX' =>
    '@claude redige a minuta de <procuração|contrato> com os dados deste cliente no ADVBOX e salva no Drive (não envia a ninguém).',
  'Claude · Resumo do caso' =>
    '@claude resume este caso em 10 linhas pro Dr. Ramon (fatos, tese, honorário, pendências).'
}.freeze

MACROS.each do |name, texto|
  macro = account.macros.find_or_initialize_by(name: name)
  macro.visibility = :global
  macro.created_by = user
  macro.updated_by = user
  macro.actions = [{ 'action_name' => 'add_private_note', 'action_params' => [texto] }]
  macro.save!
  puts "#{name} -> id=#{macro.id}"
end
