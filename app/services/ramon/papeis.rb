# Papéis comerciais (playbook operacional §13, item 1): SDR e Closer são os
# Times nativos `sdr` e `closer` (Configurações → Times); gestor = administrador
# da conta. Sem tabela própria de propósito — o Chatwoot já tem a tela de times.
module Ramon::Papeis
  module_function

  SDR = 'sdr'.freeze
  CLOSER = 'closer'.freeze
  COLUNA = { SDR => :sdr_id, CLOSER => :closer_id }.freeze

  def membro_ids(account, papel)
    account.teams.find_by(name: papel)&.members&.pluck(:id) || []
  end

  def membro?(account, user, papel)
    user.present? && membro_ids(account, papel).include?(user.id)
  end

  def gestor_ids(account)
    account.account_users.administrator.pluck(:user_id)
  end

  # Distribuição: o membro do time com menos leads abertos naquele papel
  # (empate → menor id). Com 1 pessoa é sempre ela; com 2 (mar/27) a carga
  # se equilibra sozinha. nil = time vazio (lead fica sem dono, como antes).
  def proximo(account, papel)
    ids = membro_ids(account, papel)
    return nil if ids.empty?

    coluna = COLUNA.fetch(papel)
    carga = account.leads.open.where(coluna => ids).reorder(nil).group(coluna).count
    User.find_by(id: ids.min_by { |id| [carga[id] || 0, id] })
  end

  # Reunião marcada (Cal.com) sem Closer → membro do time `closer`.
  def atribuir_closer!(lead)
    return if lead.closer_id.present?

    closer = proximo(lead.account, CLOSER)
    lead.update!(closer: closer) if closer
  end
end
