# Migração 1 a 1 do código para fluxos (spec §8 B4+, §15 e §16): o que TODA migração precisa, num lugar só.
# Cada grupo é uma automação do código: a env que liga a troca, os fluxos que a substituem (sistema_chave → gatilho
# esperado; o desenho vem de db/seeds/ramon/fluxos/migrados/<sistema_chave>.json) e, se preciso, um ajuste do desenho
# por conta. A chave: env ligada E todos os fluxos do grupo ligados, publicados, em modo normal, com o gatilho esperado
# (e sem limite do dia, salvo limite_devolve: false) → os fluxos fazem e o código para; qualquer peça fora → o código
# faz e os fluxos só ensaiam.
# Migração nova (B4.3+): uma entrada em GRUPOS + o(s) JSON + o código
# lendo assumiu? UMA vez por evento.
module Ramon::Fluxos::Migracao
  PASTA = Rails.root.join('db/seeds/ramon/fluxos/migrados')
  GRUPOS = {
    'reunioes' => {
      env: 'RAMON_FLUXO_REUNIOES', faz: 'o agendamento',
      fluxos: { 'reuniao_marcada' => 'reuniao_marcada', 'reuniao_cancelada' => 'reuniao_cancelada',
                'lembretes_reuniao' => 'reuniao_na_agenda' }.freeze,
      # mover_etapa vem sem etapa no JSON (a etapa é do funil de cada conta)
      preparar: ->(account, desenho) { Ramon::Fluxos::Reunioes.com_etapa(account, desenho) }
    },
    # B4.2: o vigia do SLA da 1ª resposta (Ramon::FirstResponseSlaJob), disparado pelo RamonLeadListener.
    'sla' => {
      env: 'RAMON_FLUXO_SLA', faz: 'o aviso de SLA da 1ª resposta',
      fluxos: { 'sla_primeira_resposta' => 'conversa_criada' }.freeze
    },
    # B4.3: a cadência de retomada (Ramon::DailyFollowUpJob e o botão "Preparar retomada"). O limite do dia é o teto do código.
    'cadencia' => {
      env: 'RAMON_FLUXO_CADENCIA', faz: 'a cadência de retomada',
      fluxos: { 'cadencia' => 'lead_parado' }.freeze, limite_devolve: false
    },
    # B4.4: o lead ganho (dossiê, NPS e caso no ADVBOX), decidido no callback do Lead (Ramon::Fluxos::LeadGanho).
    'lead_ganho' => {
      env: 'RAMON_FLUXO_LEAD_GANHO', faz: 'o lead ganho (dossiê, NPS e caso no ADVBOX)',
      fluxos: { 'lead_ganho' => 'lead_ganho' }.freeze
    },
    # B4.5: os eventos do ADVBOX (Ramon::Fluxos::EventosAdvbox). O mover_etapa vem sem etapa: a de ganho da conta (a do código).
    'eventos_advbox' => {
      env: 'RAMON_FLUXO_EVENTOS_ADVBOX', faz: 'os eventos do ADVBOX',
      fluxos: { 'eventos_advbox' => 'evento_advbox' }.freeze,
      preparar: ->(account, desenho) { Ramon::Fluxos::Migracao.com_etapa(desenho, account.lead_stages.find_by!(is_won: true).id) }
    },
    # B5-conta: o Resumo do dia (Ramon::Fluxos::ResumoDoDia), no gatilho Horário da conta. env_antiga: o nome de antes,
    # lido só sem o novo — a imagem nova sobe antes da troca na VPS sem virar a chave.
    # ponytail: apagar env_antiga quando a VPS tiver RAMON_FLUXO_RESUMO_DIA.
    'resumo_do_dia' => {
      env: 'RAMON_FLUXO_RESUMO_DIA', env_antiga: 'RAMON_FLUXO_ROTINAS', faz: 'o resumo do dia',
      fluxos: { 'resumo_do_dia' => 'horario_conta' }.freeze
    },
    # B5-externos: a chegada de cliente, decidida no RamonChegadasController.
    'chegada_cliente' => {
      env: 'RAMON_FLUXO_CHEGADA', faz: 'a escalada da chegada de cliente',
      fluxos: { 'chegada_cliente' => 'chegada_cliente' }.freeze
    }
  }.freeze

  module_function

  def grupo(nome) = GRUPOS.fetch(nome.to_s) { raise ArgumentError, "Migração desconhecida: #{nome} (há: #{GRUPOS.keys.join(', ')})" }

  def gatilhos(nome) = grupo(nome)[:fluxos]

  # Fluxo que substitui código (spec §14: fluxo próprio, origem 'usuario'), de qualquer migração.
  def migrado?(fluxo) = fluxo.origem == 'usuario' && GRUPOS.values.any? { |g| g[:fluxos].key?(fluxo.sistema_chave) }

  def ligada?(nome)
    g = grupo(nome)
    ENV.fetch(g[:env]) { ENV.fetch(g[:env_antiga], nil) if g[:env_antiga] } == 'on'
  end

  # limite_devolve (padrão true): limite do dia num fluxo do grupo devolve o comando ao código — com limite, o Disparo
  # pularia o fluxo depois do N-ésimo evento e ninguém faria. Grupo cujo código também tem teto (a cadência: 15/dia)
  # registra false. Os filtros do gatilho ficam a cargo do admin (E6: editar o fluxo pode tirar efeitos).
  def assumiu?(account, nome)
    return false unless ligada?(nome)

    atuais = account.fluxos.executaveis.where(origem: 'usuario', modo: 'normal', sistema_chave: gatilhos(nome).keys)
    atuais = atuais.where(limite_dia: nil) if grupo(nome).fetch(:limite_devolve, true)
    atuais.pluck(:sistema_chave, :gatilho_tipo).sort == gatilhos(nome).to_a.sort
  end

  def fluxos(account, nome) = account.fluxos.where(origem: 'usuario', sistema_chave: gatilhos(nome).keys).order(:id)

  def fluxo(account, chave) = account.fluxos.where(origem: 'usuario', sistema_chave: chave).order(:id).first

  # normal = os fluxos assumem; sombra = devolve ao código na hora. Todos os do grupo juntos.
  def mudar_modo!(account, nome, modo)
    lista = fluxos(account, nome).to_a
    raise ArgumentError, "Fluxos ainda não criados: rode ramon:fluxos:migracao:criar[#{nome},#{account.id}]" if lista.size < gatilhos(nome).size
    raise ArgumentError, "Ligue #{grupo(nome)[:env]}=on antes (sem ela o código continua fazendo tudo)" if modo == 'normal' && !ligada?(nome)

    Fluxo.transaction { lista.each { |fluxo| fluxo.update!(modo: modo) } }
    lista
  end

  def descrever(account, nome)
    faz = grupo(nome)[:faz]
    quem = assumiu?(account, nome) ? "os FLUXOS fazem #{faz} (o código não faz mais)" : "o CÓDIGO faz #{faz} (os fluxos ensaiam)"
    linhas = fluxos(account, nome).map { |f| "Fluxo ##{f.id} \"#{f.nome}\" — modo #{f.modo}, #{f.ativo ? 'ligado' : 'desligado'}" }
    [*linhas, "Agora #{quem}."].join("\n")
  end

  # Cria os que faltam, em sombra, ligados e publicados (com o limite do dia do JSON, se houver). Já existe → devolve
  # sem tocar (o Eduardo pode ter editado).
  def semear(account, nome) = gatilhos(nome).keys.map { |chave| fluxo(account, chave) || criar(account, nome, chave) }

  def criar(account, nome, chave)
    dados = JSON.parse(PASTA.join("#{chave}.json").read)
    preparar = grupo(nome)[:preparar]
    desenho = preparar ? preparar.call(account, dados['desenho']) : dados['desenho']
    Fluxo.transaction do
      novo = account.fluxos.create!(nome: dados['nome'], descricao: dados['descricao'], origem: 'usuario', sistema_chave: chave,
                                    modo: 'sombra', ativo: true, limite_dia: dados['limite_dia'], rascunho: desenho)
      novo.publicar!(nil)
      novo.reload
    end
  end

  # mover_etapa sem etapa no JSON recebe a etapa da conta (B4.5: a de ganho).
  def com_etapa(desenho, etapa_id)
    desenho.merge('nos' => desenho['nos'].map { |n| n['tipo'] == 'mover_etapa' ? n.deep_merge('config' => { 'etapa_id' => etapa_id }) : n })
  end

  # B5-leads: a decisão de um evento, lida UMA vez — dispara os fluxos migrados do grupo com 'assumido' (só eles ouvem;
  # 'migracao' separa grupos que dividem o gatilho) e roda o código (o bloco) se o fluxo não está no comando OU não pegou
  # este evento (reserva: ocupado com o mesmo alvo, filtro editado, erro do motor). Nunca em dobro, nunca nenhum.
  def decidir(nome, gatilho, alvo, dados = {})
    assumido = assumiu?(alvo.account, nome)
    feitas = Ramon::Fluxos::Disparo.externo(gatilho, alvo, dados.merge('assumido' => assumido, 'migracao' => nome))
    yield unless assumido && feitas.any?
  end
end
