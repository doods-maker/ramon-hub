# Programa de Metas do híbrido (modelo B; kit `comercial\contratacao\09-termo-de-metas.md`), um por trimestre, lançado
# pelo gestor na tela Extrato. Regras (valores em reais, já com DSR se houver — o extrato não soma DSR por cima):
#   faixas     [{ min, valor }]                  bônus do mês = a faixa mais alta atingida (não somam)
#   gas        { acima_de, valor }               cada contrato apto acima de N no mês paga + valor
#   constancia { min_mes, max_problemas, valor } paga no extrato do mês seguinte ao fim do trimestre
class ProgramaMetas < ApplicationRecord
  self.table_name = 'ramon_programas_metas'

  belongs_to :account

  audited only: %w[inicio fim regras], associated_with: :account

  validates :inicio, :fim, presence: true
  validate :fim_depois_do_inicio
  validate :sem_sobreposicao

  # Programa que vale no mês (o mês inteiro dentro da vigência).
  def self.do_mes(account, mes)
    where(account: account).where(inicio: ..mes.beginning_of_month, fim: mes.end_of_month..).order(:inicio).last
  end

  # Programa cujo trimestre terminou no mês anterior (a constância é paga no mês seguinte).
  def self.encerrado_antes_de(account, mes)
    anterior = mes.beginning_of_month.prev_month
    where(account: account, fim: anterior..anterior.end_of_month).order(:fim).last
  end

  # Bônus do mês pela contagem de contratos aptos: a faixa mais alta atingida (não somam) e o gás acima de N.
  def bonus_do_mes(contagem)
    [faixa(contagem), gas(contagem)].compact
  end

  # A próxima faixa acima da contagem (o "quanto falta" do cartão); nil se já passou da última.
  def proxima_faixa(contagem)
    faixa = Array(regras['faixas']).select { |f| f['min'].to_i > contagem }.min_by { |f| f['min'].to_i }
    faixa && { min: faixa['min'].to_i, valor: faixa['valor'].to_f, faltam: faixa['min'].to_i - contagem }
  end

  private

  def faixa(contagem)
    atingida = Array(regras['faixas']).select { |f| contagem >= f['min'].to_i }.max_by { |f| f['min'].to_i }
    atingida && { tipo: 'faixa', valor: atingida['valor'].to_f }
  end

  def gas(contagem)
    acima = contagem - regras.dig('gas', 'acima_de').to_i
    regras['gas'] && acima.positive? ? { tipo: 'gas', valor: (acima * regras['gas']['valor'].to_d).to_f } : nil
  end

  def sem_sobreposicao
    return unless inicio && fim

    outros = self.class.where(account_id: account_id).where.not(id: id).where(inicio: ..fim, fim: inicio..)
    errors.add(:inicio, :taken) if outros.exists?
  end

  def fim_depois_do_inicio
    errors.add(:fim, :invalid) if inicio && fim && fim < inicio
  end
end
