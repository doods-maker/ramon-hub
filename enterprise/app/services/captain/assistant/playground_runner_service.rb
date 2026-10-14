# ramon (roteiro F2): Testar com tese — o roteiro em teste vai no state das tools (Ramon::Roteiro::Teste), que
# devolvem o estado novo nele. Subclasse para não mexer no AgentRunnerService (no teto do ClassLength).
class Captain::Assistant::PlaygroundRunnerService < Captain::Assistant::AgentRunnerService
  def initialize(roteiro_teste:, **)
    super(**)
    @roteiro_teste = roteiro_teste
  end

  private

  def build_state
    super.merge(roteiro_teste: @roteiro_teste)
  end
end
