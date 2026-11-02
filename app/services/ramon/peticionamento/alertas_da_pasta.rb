# Cruza a leitura da petição com a pasta/cliente. `alertas` travam a confirmação; `avisos` só informam.
# Recalculado a cada chamada: corrigir o número na conferência resolve o alerta.
class Ramon::Peticionamento::AlertasDaPasta
  def self.call(peticao) = new(peticao).call

  def initialize(peticao)
    @peticao = peticao
    @leitura = peticao.leitura || {}
  end

  def call
    alertas = []
    avisos = Array(@leitura['avisos']).dup
    alertas << 'cpf_diferente' if cpf_diferente?
    processo = conferir_processo
    alertas << processo if processo == 'processo_fora_do_cliente'
    avisos << processo if processo == 'espelho_vazio'
    { alertas: alertas, avisos: avisos.uniq }
  end

  private

  def digitos(valor) = valor.to_s.delete('^0-9')

  def cpf_diferente?
    pasta = digitos(@leitura['cpf_pasta'])
    peca = digitos(@leitura.dig('campos', 'cpf'))
    pasta.present? && peca.present? && pasta != peca
  end

  def conferir_processo
    numero = Ramon::Peticionamento::Cnj.normalizar(@peticao.numero_processo)
    cpf = digitos(@peticao.contact&.cpf)
    return nil if numero.nil? || cpf.blank?

    lista = numeros_do_cliente(cpf)
    return 'espelho_vazio' if lista.empty?

    'processo_fora_do_cliente' unless lista.include?(numero)
  end

  def numeros_do_cliente(cpf)
    portal = PortalCliente.find_by(account_id: @peticao.account_id, cpf: cpf)
    Array(portal&.processos).filter_map { |p| Ramon::Peticionamento::Cnj.normalizar(p['numero']) }
  end
end
