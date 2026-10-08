# B5 (decisão do Eduardo 07/10): registro das rotinas prontas do hub (passo `rotina`). Cada plano põe as suas num
# arquivo próprio, app/services/ramon/fluxos/rotinas/<plano>.rb (Ramon::Fluxos::Rotinas::<Plano>), achado aqui sozinho:
# plano novo não mexe em lista compartilhada. Contrato de cada módulo (plano B5-conta, "Contrato para os planos irmãos"):
# - ROTINAS = { 'nome' => 'conta' | 'lead' | 'conversa' | 'outro' } — o alvo; 'conta' só no gatilho Horário da conta;
#   'outro' = o registro de um evento de fora do funil (B5-externos: chegada, reunião gravada, peça, Painel do Cliente);
# - rodar(nome, ctx) → String (o resumo da trilha) ou Hash { resumo:, vars: }; no ensaio só descreve ("faria: …");
# - opcional GRUPOS (formato de Migracao::GRUPOS — vai para lá) e PENDENTE = { 'nome' => ->(account) { Boolean } }.
# As 5 rotinas da B4.4 (Passos::Rotina::ROTINAS) seguem lá, de lead.
module Ramon::Fluxos::Rotinas
  PASTA = Rails.root.join('app/services/ramon/fluxos/rotinas')

  module_function

  def modulos
    @modulos ||= PASTA.glob('*.rb').sort.map { |arquivo| "Ramon::Fluxos::Rotinas::#{arquivo.basename('.rb').to_s.camelize}".constantize }
  end

  # nome → módulo. ponytail: refeito a cada chamada (poucos módulos, poucas rotinas); memoizar se aparecer em perfil.
  def catalogo
    modulos.each_with_object({}) do |modulo, lista|
      modulo::ROTINAS.each_key do |nome|
        raise ArgumentError, "rotina repetida: #{nome}" if lista.key?(nome) || Ramon::Fluxos::Passos::Rotina::ROTINAS.include?(nome)

        lista[nome] = modulo
      end
    end
  end

  def alvo(nome)
    return 'lead' if Ramon::Fluxos::Passos::Rotina::ROTINAS.include?(nome)

    catalogo[nome]&.then { |modulo| modulo::ROTINAS[nome] }
  end

  def grupos
    modulos.select { |modulo| modulo.const_defined?(:GRUPOS, false) }.map { |modulo| modulo::GRUPOS }
           .reduce({}) { |todos, grupo| todos.merge(grupo) { |chave| raise ArgumentError, "grupo de migração repetido: #{chave}" } }
  end

  # nil = a rotina não diz (conta como "tem o que fazer").
  def pendente(nome, account)
    modulo = catalogo[nome]
    return unless modulo&.const_defined?(:PENDENTE, false) && modulo::PENDENTE.key?(nome)

    modulo::PENDENTE[nome].call(account)
  end

  def rodar(nome, ctx)
    modulo = catalogo[nome] || raise(Ramon::Fluxos::PassoImpossivel, "rotina desconhecida: #{nome}")
    if modulo::ROTINAS[nome] == 'conta' && !ctx.execucao.alvo.is_a?(Account)
      raise Ramon::Fluxos::PassoImpossivel, 'esta rotina é da conta toda (gatilho Horário da conta)'
    end

    resultado = modulo.rodar(nome, ctx)
    { saida: 's' }.merge(resultado.is_a?(Hash) ? resultado : { resumo: resultado })
  end
end
