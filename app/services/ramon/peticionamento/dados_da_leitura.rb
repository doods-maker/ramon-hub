# Transforma a leitura da peça (LerPeca) em dados do hub: cliente (só pelo CPF) e advogado responsável.
# Sem certeza, fica nil e o campo vai para `incertos`. Nunca assume quem apontou a pasta.
class Ramon::Peticionamento::DadosDaLeitura
  OAB_DR_RAMON = '19044'.freeze # ponytail: titular fixo; virar configuração se houver segundo titular

  def self.call(account, lida) = new(account, lida || {}).call

  def initialize(account, lida)
    @account = account
    @lida = lida
  end

  def call
    responsavel, duvida = achar_responsavel
    incertos = Array(@lida['incertos']).map(&:to_s)
    incertos |= ['responsavel'] if responsavel.nil? || duvida
    {
      inicial: { 'inicial' => true, 'intermediaria' => false }[@lida['tipo']],
      numero_processo: @lida['numero_processo'], tribunal: @lida['tribunal'],
      contact: achar_contato, responsavel: responsavel, descricao: @lida['titulo'], incertos: incertos
    }
  end

  private

  def achar_contato
    cpf = @lida['cpf'].to_s.delete('^0-9')
    @account.contacts.find_by(cpf: cpf) if cpf.length == 11
  end

  # Associado (OAB diferente da do Dr. Ramon) tem preferência, o primeiro se houver vários; Dr. Ramon sozinho é ele.
  # Devolve [usuário, duvida]: dúvida se havia vários associados ou se o nome do usuário tem um token só.
  def achar_responsavel
    assinantes = Array(@lida['assinantes']).select { |a| a.is_a?(Hash) }
    escolhido, outros = escolher_assinante(assinantes)
    return [nil, true] if escolhido.nil?

    alvo = tokens(escolhido['nome'])
    candidatos = elegiveis.select { |u| (t = tokens(u.name)).any? && (t - alvo).empty? }
    return [nil, true] unless candidatos.size == 1

    [candidatos.first, outros || tokens(candidatos.first.name).size == 1]
  end

  def escolher_assinante(assinantes)
    associados = assinantes.reject { |a| a['oab'].to_s.delete('^0-9') == OAB_DR_RAMON }
    [associados.first || assinantes.first, associados.size > 1]
  end

  def elegiveis
    ids = Ramon::Papeis.gestor_ids(@account) | Ramon::Papeis.membro_ids(@account, Ramon::Papeis::JURIDICO)
    User.where(id: ids).to_a
  end

  def tokens(nome) = I18n.transliterate(nome.to_s).downcase.scan(/[a-z]+/).uniq
end
