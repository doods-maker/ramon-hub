# B4.3 (spec §8): a cadência de retomada (W4) saindo do código para um fluxo, direto (sem sombra). A chave e a semeadura
# são da migração genérica (Ramon::Fluxos::Migracao, grupo 'cadencia').
module Ramon::Fluxos::Retomada
  GRUPO = 'cadencia'.freeze # a migração (Ramon::Fluxos::Migracao::GRUPOS) e o sistema_chave do fluxo

  module_function

  # Só o fluxo da cadência (o Migracao.migrado? genérico pegaria os das outras migrações).
  def migrado?(fluxo) = fluxo.origem == 'usuario' && fluxo.sistema_chave == GRUPO
end
