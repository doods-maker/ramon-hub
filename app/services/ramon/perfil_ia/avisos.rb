# Avisos de dependência da tela "Como a IA atende" (spec, sugestão 4): o perfil deixa a IA fazer algo que não vai sair
# porque falta uma peça fora do perfil. Contra o perfil EFETIVO do alvo (tese/caixa sem cfg = o padrão, que vale nela).
# { 'tese:3' => [{ acao:, tipo:, link: }] } — acao nil = aviso do alvo todo; link = para onde a tela leva
# (playbooks | agenda | roteiro | caixas). Alvo sem aviso não aparece.
module Ramon::PerfilIa::Avisos
  module_function

  def de(account)
    sem_google = !GoogleAgendaConta.conectadas.exists?(user_id: Ramon::Papeis.membro_ids(account, Ramon::Papeis::CLOSER))
    padrao = Ramon::PerfilIa.cfg_salvo(account, 'padrao') || Ramon::PerfilIa::INICIAL
    avisos = { 'padrao' => comuns(account, padrao, sem_google) }
    avisos.merge(teses(account, padrao, sem_google), caixas(account, padrao, sem_google)).reject { |_, lista| lista.empty? }
  end

  def teses(account, padrao, sem_google)
    passos = RoteiroPasso.where(account_id: account.id).to_a
    account.theses.to_h do |tese|
      cfg = Ramon::PerfilIa.cfg_salvo(account, 'teses', tese.id) || padrao
      ["tese:#{tese.id}", comuns(account, cfg, sem_google) + da_tese(account, tese, cfg) + do_roteiro(tese, passos)]
    end
  end

  def caixas(account, padrao, sem_google)
    Ramon::PerfilIa::Tela.caixas(account).to_h do |caixa|
      cfg = Ramon::PerfilIa.cfg_salvo(account, 'caixas', caixa.id)
      sem_ia = cfg && !Ramon::PerfilIa.com_ia?(caixa) ? [{ acao: nil, tipo: 'sem_assistente', link: 'caixas' }] : []
      ["caixa:#{caixa.id}", comuns(account, cfg || padrao, sem_google) + sem_ia]
    end
  end

  # Só a permissão da ação (o Marcador não entra: o aviso é sobre a peça que falta).
  def permissao(account, cfg, acao) = Ramon::PerfilIa.new(nil, Lead.new(account: account), 'aviso', cfg, :aviso).permissao(acao)

  # Ninguém do time closer com o Google conectado: a reunião vira sugestão (vale para a conta toda).
  def comuns(account, cfg, sem_google)
    sem_google && permissao(account, cfg, 'marcar_reuniao') == :sozinha ? [{ acao: 'marcar_reuniao', tipo: 'sem_google', link: 'agenda' }] : []
  end

  def da_tese(account, tese, cfg)
    [(%w[contrato_zapsign sem_zapsign] if tese.zapsign_template_id.blank?),
     (%w[citar_honorario fora_da_tabela] unless tese.honorario_na_tabela)].compact.filter_map do |acao, tipo|
      { acao: acao, tipo: tipo, link: 'playbooks' } if permissao(account, cfg, acao) != :nunca
    end
  end

  # Tese com roteiro próprio em que nenhuma saída (dela ou dos passos comuns) é "Qualificado (fim)".
  def do_roteiro(tese, passos)
    proprios = passos.select { |p| p.thesis_id == tese.id }
    return [] if proprios.empty?

    termina = (proprios + passos.select { |p| p.thesis_id.nil? }).any? { |p| Array(p.saidas).any? { |s| s['acao'] == 'concluir' } }
    termina ? [] : [{ acao: nil, tipo: 'sem_qualificado', link: 'roteiro' }]
  end
end
