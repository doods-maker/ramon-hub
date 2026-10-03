# Conteúdo do Instagram: só administrador (Eduardo) aprova, agenda e publica.
class PecaPolicy < ApplicationPolicy
  %i[index? show? aprovar? reprovar? atualizar_legenda? refazer? agendar? publicar_agora?
     cancelar_agendamento? tentar_de_novo?].each do |acao|
    define_method(acao) { @account_user.administrator? }
  end
end
