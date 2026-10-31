# Equipe · chat interno (Fatia 2), isolado das conversas de cliente. Quem
# participa: geral = usuários da conta; setor = membros do time (a fonte da
# verdade é o time); direto = as 2 linhas de ramon_chat_membros. Administrador
# lê qualquer canal mas não vira membro (ChatCanalPolicy). Nas linhas de membro
# de geral/setor só mora o lido_ate, criadas sob demanda.
class ChatCanal < ApplicationRecord
  self.table_name = 'ramon_chat_canais'

  TIPOS = %w[direto setor geral].freeze

  belongs_to :account
  belongs_to :team, optional: true
  has_many :membros, class_name: 'ChatMembro', foreign_key: :canal_id, inverse_of: :canal, dependent: :delete_all
  has_many :mensagens, class_name: 'ChatMensagem', foreign_key: :canal_id, inverse_of: :canal, dependent: :delete_all

  validates :tipo, inclusion: { in: TIPOS }

  # Garante o Geral e um canal por time; o administrador vê todos, os demais só
  # onde participam. Canal de setor cujo time foi apagado some da lista.
  def self.visiveis(account, user, admin:)
    garantir_fixos!(account)
    canais = account.chat_canais.includes(:team, membros: :user).order(:id).reject { |c| c.tipo == 'setor' && c.team.nil? }
    admin ? canais : canais.select { |c| c.participante?(user) }
  end

  def self.garantir_fixos!(account)
    existentes = account.chat_canais.pluck(:chave)
    fixos = [{ chave: 'geral', tipo: 'geral' }] +
            account.teams.map { |team| { chave: "setor:#{team.id}", tipo: 'setor', team_id: team.id } }
    fixos.reject { |f| existentes.include?(f[:chave]) }.each { |f| account.chat_canais.create_or_find_by!(f) }
  end

  def self.direto!(account, user, outro)
    ids = [user.id, outro.id].sort
    chave = "direto:#{ids.join('-')}"
    account.chat_canais.find_by(chave: chave) || transaction do
      canal = account.chat_canais.create!(tipo: 'direto', chave: chave)
      ids.each { |id| canal.membros.create!(user_id: id) }
      canal
    end
  end

  def membro_ids
    @membro_ids ||= case tipo
                    when 'geral' then account.account_users.pluck(:user_id)
                    when 'setor' then team.members.pluck(:id)
                    else membros.map(&:user_id)
                    end
  end

  def participante?(user) = membro_ids.include?(user.id)

  # As do próprio usuário nunca contam; quem nunca leu tem tudo por ler.
  def nao_lidas(user)
    return 0 unless participante?(user)

    lido_ate = membros.find { |m| m.user_id == user.id }&.lido_ate
    escopo = mensagens.where.not(autor_id: user.id)
    escopo = escopo.where('created_at > ?', lido_ate) if lido_ate
    escopo.count
  end

  # Administrador lendo canal alheio não vira membro (a linha de membro do direto É a participação).
  def marcar_lido!(user)
    return unless participante?(user)

    membros.find_or_create_by!(user_id: user.id).update!(lido_ate: Time.current)
  end

  # nome nil = Geral (o front traduz). Direto: o outro; visto de fora (admin), os dois.
  def push_data(user)
    { id: id, tipo: tipo, nome: nome_para(user), participante: participante?(user), nao_lidas: nao_lidas(user) }
  end

  private

  def nome_para(user)
    case tipo
    when 'geral' then nil
    when 'setor' then team.name
    else membros.map(&:user).reject { |u| u.id == user.id }.map(&:name).join(' · ')
    end
  end
end
