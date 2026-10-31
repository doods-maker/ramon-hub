class RamonPeticaoPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || Ramon::Papeis.membro?(@account, @user, Ramon::Papeis::JURIDICO)
  end

  %i[show create update destroy arquivos arquivos_drive atualizar_arquivo remover_arquivo ordem registrar_protocolo drive drive_busca
     processos].each do |acao|
    define_method(:"#{acao}?") { index? }
  end
end
