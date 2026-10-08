# B5-leads: leads e conversas pelos fluxos — criar lead, origem, sugestão de documento, coach de objeção e o aviso ao
# agente do hub. Cada uma é uma migração (GRUPOS, juntado em Migracao::GRUPOS pelo registro); o ouvinte decide por
# Ramon::Fluxos::Migracao.decidir, com reserva. Na carga este módulo não cita Ramon::Fluxos::Migracao (autoload circular).
module Ramon::Fluxos::Rotinas::Leads
  GRUPOS = {
    'criar_lead' => { env: 'RAMON_FLUXO_CRIAR_LEAD', faz: 'a criação do lead', fluxos: { 'criar_lead_da_conversa' => 'conversa_criada' }.freeze },
    'origem_lead' => { env: 'RAMON_FLUXO_ORIGEM_LEAD', faz: 'a origem do lead', fluxos: { 'origem_do_lead' => 'mensagem_recebida' }.freeze },
    'sugestao_doc' => { env: 'RAMON_FLUXO_SUGESTAO_DOC', faz: 'a sugestão de documento',
                        fluxos: { 'sugestao_documento' => 'mensagem_recebida' }.freeze },
    'coach' => { env: 'RAMON_FLUXO_COACH', faz: 'o coach de objeção', fluxos: { 'coach_objecao' => 'mensagem_recebida' }.freeze },
    'agente' => { env: 'RAMON_FLUXO_AGENTE', faz: 'o aviso ao agente do hub', fluxos: { 'agente_hub' => 'nota_escrita' }.freeze }
  }.freeze
  # ponytail: provisório — as rotinas (e o rodar) chegam na Task 3.
  ROTINAS = {}.freeze
end
