# ramon (roteiro F2): Testar com tese — o roteiro em teste vai no state das tools (Ramon::Roteiro::Teste), que
# devolvem o estado novo nele. Subclasse para não mexer no AgentRunnerService (no teto do ClassLength).
# ramon (Perfil da IA): o Perfil do teste (cfg da tela, mesmo não salvo) dá as Tools bloqueadas e os gatilhos do turno;
# o controller lê o mesmo perfil para a decisão debaixo da resposta.
class Captain::Assistant::PlaygroundRunnerService < Captain::Assistant::AgentRunnerService
  attr_reader :perfil

  def initialize(roteiro_teste:, **)
    super(**)
    @roteiro_teste = roteiro_teste
    @perfil = Ramon::Roteiro::Teste.perfil(@assistant.account, roteiro_teste)
  end

  private

  def build_state
    super.merge(roteiro_teste: @roteiro_teste, ramon_gatilhos: @perfil.textos_dos_gatilhos)
  end

  def tools_bloqueadas = @perfil.tools_bloqueadas
end
