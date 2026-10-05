# Erro que não adianta repetir (ex.: passo de lead numa conversa sem lead):
# o executor marca `falhou` na hora, sem as 3 tentativas.
class Ramon::Fluxos::PassoImpossivel < StandardError; end
