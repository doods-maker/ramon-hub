require 'rails_helper'

# Valores da spec (comercial\docs\2026-11-09-briefing-hub-extrato-duas-grades.md):
# A = SDR R$ 8 até a meta (50) e R$ 12 acima; Closer R$ 30 até a meta (20) e R$ 45 acima; × fator.
# B = híbrido, comissão da tese por contrato apto + Programa de Metas do trimestre.
# DSR = variável × (domingos e feriados ÷ dias de seg a sáb).
#   nov/2026: 5 domingos + 02/11 e 20/11 = 7; 30 − 7 = 23 dias → 7/23.
#   dez/2026: 4 domingos + 25/12 = 5; 31 − 5 = 26 dias → 5/26.
RSpec.describe Ramon::ExtratoVariavel do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.order(:position).first }
  let(:sdr) { create(:user, account: account, role: :agent, name: 'Sara SDR') }
  let(:closer) { create(:user, account: account, role: :agent, name: 'Caio Closer') }
  let(:novembro) { Date.new(2026, 11, 1) }
  let(:dezembro) { Date.new(2026, 12, 1) }
  let(:tese) { create(:thesis, account: account, name: 'Tese do extrato', comissao_apto: 25) }

  before do
    create(:team_member, team: create(:team, account: account, name: 'sdr'), user: sdr)
    create(:team_member, team: create(:team, account: account, name: 'closer'), user: closer)
  end

  def em(mes, dia = 10) = Time.find_zone('America/Sao_Paulo').local(mes.year, mes.month, dia, 12)

  def reunioes(qtd, mes: novembro, resultado: 'qualificada')
    qtd.times do |i|
      create(:lead, account: account, lead_stage: stage, sdr: sdr, reuniao_resultado: resultado, reuniao_registrada_em: em(mes) + i.minutes)
    end
  end

  # validado pelo jurídico (apto_por_id); por_prazo: true = apto sozinho pelos 5 dias úteis
  def aptos(qtd, mes: novembro, thesis: tese, por_prazo: false)
    qtd.times do |i|
      create(:lead, account: account, lead_stage: stage, closer: closer, thesis: thesis).tap do |lead|
        lead.update_columns(contrato_limpo_em: em(mes, 3), apto_em: em(mes) + i.minutes, # rubocop:disable Rails/SkipsModelValidations
                            apto_por_id: por_prazo ? nil : sdr.id)
      end
    end
  end

  def extrato_de(user, mes = novembro)
    described_class.new(account: account, mes: mes).pessoas.find { |p| p[:user][:id] == user.id }
  end

  # admissão em novembro (o mês da 1ª meta não tem Programa)
  def hibrido!(mes = novembro) = MetaComercial.create!(account: account, user: closer, papel: 'hibrido', mes: mes, meta: 0)

  def programa!
    ProgramaMetas.create!(account: account, inicio: dezembro, fim: Date.new(2027, 2, 28),
                          regras: { 'faixas' => [{ 'min' => 25, 'valor' => 300 }, { 'min' => 35, 'valor' => 450 }],
                                    'gas' => { 'acima_de' => 40, 'valor' => 25 },
                                    'constancia' => { 'min_mes' => 25, 'max_problemas' => 0.05, 'valor' => 600 } })
  end

  describe 'modelo A (SDR e Closer separados)' do
    it 'SDR: 50 reuniões qualificadas na meta padrão = R$ 400 + DSR', :aggregate_failures do
      reunioes(50)
      reunioes(3, resultado: 'nao_qualificada')

      linha = extrato_de(sdr)
      expect(linha).to include(papel: 'sdr', meta: 50, contagem: 50, variavel: 400.0, dsr: 121.74, total: 521.74)
    end

    it 'SDR: acima da meta cada reunião vale R$ 12 (100 reuniões = R$ 1.000)' do
      reunioes(100)

      expect(extrato_de(sdr)[:variavel]).to eq(1000.0)
    end

    it 'Closer: contrato apto vale R$ 30 até 20 e R$ 45 acima (50 = R$ 1.950)', :aggregate_failures do
      aptos(20)
      expect(extrato_de(closer)).to include(papel: 'closer', variavel: 600.0)

      aptos(30)
      expect(extrato_de(closer)[:variavel]).to eq(1950.0)
    end

    it 'a meta lançada pelo gestor muda onde começa o valor de cima' do
      MetaComercial.create!(account: account, user: sdr, papel: 'sdr', mes: novembro, meta: 2)
      reunioes(3)

      expect(extrato_de(sdr)[:unidades].pluck(:valor)).to eq([8, 8, 12])
    end

    it 'o fator do trimestre multiplica as unidades antes do DSR (0,8 e 1,1)', :aggregate_failures do
      MetaComercial.create!(account: account, user: sdr, papel: 'sdr', mes: novembro, meta: 50, fator: 0.8)
      MetaComercial.create!(account: account, user: closer, papel: 'closer', mes: novembro, meta: 20, fator: 1.1)
      reunioes(50)
      aptos(20)

      expect(extrato_de(sdr)).to include(fator: 0.8, variavel: 320.0, dsr: 97.39)
      expect(extrato_de(closer)).to include(fator: 1.1, variavel: 660.0)
    end

    it 'o fator lançado vale nos meses seguintes até o gestor lançar outro' do
      MetaComercial.create!(account: account, user: closer, papel: 'closer', mes: novembro, meta: 20, fator: 1.1)
      aptos(20, mes: dezembro)

      expect(extrato_de(closer, dezembro)).to include(fator: 1.1, variavel: 660.0)
    end

    it 'o apto por prazo aparece como evento próprio e paga igual', :aggregate_failures do
      aptos(1, por_prazo: true)

      expect(extrato_de(closer)[:unidades]).to contain_exactly(include(evento: 'contrato_apto_prazo', valor: 30.0))
    end

    it 'conta no mês pelo fuso de São Paulo (01/12 00:30 BRT já é dezembro)' do
      create(:lead, account: account, lead_stage: stage, sdr: sdr, reuniao_resultado: 'qualificada',
                    reuniao_registrada_em: Time.zone.parse('2026-12-01 03:30:00 UTC'))

      expect(extrato_de(sdr)[:contagem]).to eq(0)
    end
  end

  describe 'modelo B (híbrido)' do
    it 'comissão da tese por contrato apto, faixa do Programa e gás acima de 40; bônus sem DSR', :aggregate_failures do
      hibrido!
      programa!
      aptos(41, mes: dezembro)

      linha = extrato_de(closer, dezembro)
      expect(linha).to include(papel: 'hibrido', contagem: 41, variavel: 1025.0, dsr: 197.12)
      expect(linha[:bonus]).to contain_exactly(include(tipo: 'faixa', valor: 450), include(tipo: 'gas', valor: 25))
      expect(linha[:total]).to eq(1697.12) # 1.025 + 197,12 + 450 + 25
    end

    it '20, 35 e 50 aptos: só comissão; faixa de cima; faixa de cima + gás de 10 contratos', :aggregate_failures do
      hibrido!
      programa!
      janeiro = Date.new(2027, 1, 1)
      fevereiro = Date.new(2027, 2, 1)
      aptos(20, mes: dezembro)
      aptos(35, mes: janeiro)
      aptos(50, mes: fevereiro)

      expect(extrato_de(closer, dezembro)).to include(variavel: 500.0, bonus: [])
      expect(extrato_de(closer, janeiro)[:bonus]).to contain_exactly(include(tipo: 'faixa', valor: 450))
      expect(extrato_de(closer, fevereiro)[:bonus]).to contain_exactly(include(tipo: 'faixa', valor: 450), include(tipo: 'gas', valor: 250))
    end

    it '50 aptos em dezembro: R$ 1.250 + DSR 5/26 + R$ 450 + R$ 250 de gás' do
      hibrido!
      programa!
      aptos(50, mes: dezembro)

      expect(extrato_de(closer, dezembro)).to include(variavel: 1250.0, dsr: 240.38, total: 2190.38)
    end

    it 'faixa de baixo com 25 a 34' do
      hibrido!
      programa!
      aptos(25, mes: dezembro)

      expect(extrato_de(closer, dezembro)[:bonus]).to contain_exactly(include(tipo: 'faixa', valor: 300))
    end

    it 'admitido no meio do trimestre: o 1º mês é só comissão' do
      hibrido!(Date.new(2027, 1, 1))
      programa!
      aptos(30, mes: Date.new(2027, 1, 1))

      expect(extrato_de(closer, Date.new(2027, 1, 1))[:bonus]).to be_empty
    end

    it 'tese sem comissão não paga e fica marcada', :aggregate_failures do
      hibrido!
      aptos(1, mes: dezembro, thesis: create(:thesis, account: account, name: 'Tese sem comissão'))

      expect(extrato_de(closer, dezembro)).to include(variavel: 0.0, sem_valor: 1)
    end

    it 'mês sem Programa vigente: só comissão (mês de admissão)' do
      hibrido!(novembro)
      programa!
      aptos(30)

      expect(extrato_de(closer)[:bonus]).to be_empty
    end

    it 'o papel lançado vale nos meses seguintes até o gestor lançar outro' do
      hibrido!(dezembro)
      aptos(1, mes: Date.new(2027, 1, 1))

      expect(extrato_de(closer, Date.new(2027, 1, 1))[:papel]).to eq('hibrido')
    end

    describe 'constância (no extrato do mês seguinte ao trimestre)' do
      let(:trimestre) { [dezembro, Date.new(2027, 1, 1), Date.new(2027, 2, 1)] }
      let(:marco) { Date.new(2027, 3, 1) }

      before do
        hibrido!
        programa!
        trimestre.each { |mes| aptos(25, mes: mes) }
      end

      it '25 ou mais aptos em cada mês e até 5% de devolvidos = R$ 600' do
        devolver(1)

        expect(extrato_de(closer, marco)[:bonus]).to contain_exactly(include(tipo: 'constancia', valor: 600))
      end

      it 'mais de 5% devolvidos ou cancelados depois de aptos = sem constância' do
        devolver(2) # + 2 cancelados depois de aptos = 4 de 75 enviados (5,3%)
        account.leads.where(closer: closer).order(:id).offset(2).limit(2)
               .update_all(contrato_cancelado_em: em(Date.new(2027, 1, 1), 20)) # rubocop:disable Rails/SkipsModelValidations

        expect(extrato_de(closer, marco)[:bonus]).to be_empty
      end

      def devolver(qtd)
        account.leads.where(closer: closer).order(:id).limit(qtd).each do |lead|
          lead.lead_activities.create!(account: account, kind: 'apto_devolvido', to_value: 'Falta o laudo', created_at: em(dezembro, 5))
        end
      end
    end
  end

  describe 'quem agendou (só a reunião marcada pela IA deixa de pagar o SDR)' do
    it 'reunião registrada sobre tarefa sem criador (IA) fica fora e aparece separada', :aggregate_failures do
      pela_ia = create(:lead, account: account, lead_stage: stage, sdr: sdr)
      pela_ia.lead_tasks.create!(account: account, user: nil, title: 'Reunião', kind: 'meeting', due_at: em(novembro, 9))
      pelo_sdr = create(:lead, account: account, lead_stage: stage, sdr: sdr)
      pelo_sdr.lead_tasks.create!(account: account, user: sdr, title: 'Reunião', kind: 'meeting', due_at: em(novembro, 9))

      travel_to(em(novembro)) { [pela_ia, pelo_sdr].each { |lead| lead.registrar_reuniao!('qualificada', closer) } }

      expect(pela_ia.reload.reuniao_pela_ia).to be(true)
      expect(extrato_de(sdr)).to include(contagem: 1, reunioes_ia: 1)
    end
  end

  describe 'fator automático do trimestre (modelo A)' do
    let(:fevereiro) { Date.new(2027, 2, 1) }

    def no_shows(qtd, mes: dezembro)
      qtd.times do
        lead = create(:lead, account: account, lead_stage: stage, sdr: sdr)
        lead.lead_activities.create!(account: account, kind: 'meeting_no_show', to_value: 'Reunião', created_at: em(mes, 5))
      end
    end

    def enviados(qtd, mes: dezembro)
      Array.new(qtd) do |i|
        create(:lead, account: account, lead_stage: stage, closer: closer, thesis: tese).tap do |lead|
          lead.update_columns(contrato_limpo_em: em(mes, 3), apto_em: em(mes, 10) + i.minutes, apto_por_id: sdr.id) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end

    it 'SDR: comparecimento do trimestre anterior abaixo de 65% = 0,8 (10 realizadas, 6 faltas = 62,5%)', :aggregate_failures do
      reunioes(10, mes: dezembro)
      no_shows(6)
      reunioes(50, mes: fevereiro)

      linha = travel_to(em(fevereiro, 15)) { extrato_de(sdr, fevereiro) }
      expect(linha).to include(fator: 0.8, variavel: 320.0)
      expect(linha[:fator_base]).to include(tipo: 'comparecimento', numerador: 10, denominador: 16, manual: false)
    end

    it 'a conta do fator marca quantas realizadas e faltas vieram de reunião marcada pela IA (e elas contam)', :aggregate_failures do
      reunioes(10, mes: dezembro)
      account.leads.where(sdr_id: sdr.id).limit(2).update_all(reuniao_pela_ia: true) # rubocop:disable Rails/SkipsModelValidations
      no_shows(6)
      LeadActivity.where(kind: 'meeting_no_show').limit(1).update_all(from_value: 'ia') # rubocop:disable Rails/SkipsModelValidations

      linha = travel_to(em(fevereiro, 15)) { extrato_de(sdr, fevereiro) }
      expect(linha[:fator]).to eq(0.8)
      expect(linha[:fator_base]).to include(numerador: 10, denominador: 16, realizadas_ia: 2, faltas_ia: 1)
    end

    it 'falta em reunião marcada pela IA (tarefa sem criador) fica marcada como da IA no histórico' do
      lead = create(:lead, account: account, lead_stage: stage, sdr: sdr)
      tarefa = lead.lead_tasks.create!(account: account, user: nil, title: 'Reunião', kind: 'meeting', due_at: em(dezembro))

      tarefa.complete!(closer, no_show: true)

      expect(lead.lead_activities.find_by(kind: 'meeting_no_show').from_value).to eq('ia')
    end

    it 'SDR: acima de 80% = 1,1 (10 realizadas, 1 falta = 90,9%)' do
      reunioes(10, mes: dezembro)
      no_shows(1)

      expect(travel_to(em(fevereiro, 15)) { extrato_de(sdr, fevereiro) }[:fator]).to eq(1.1)
    end

    it 'Closer: devolvidos ou cancelados em até 90 dias acima de 15% = 0,8; até 5% = 1,1', :aggregate_failures do
      casos = enviados(20)
      casos.first(2).each { |lead| lead.lead_activities.create!(account: account, kind: 'apto_devolvido', created_at: em(dezembro, 6)) }
      casos.last(2).each { |lead| lead.update_columns(contrato_cancelado_em: em(Date.new(2027, 1, 1), 20)) } # rubocop:disable Rails/SkipsModelValidations

      expect(travel_to(em(fevereiro, 15)) { extrato_de(closer, fevereiro) }).to include(fator: 0.8)
    end

    it 'Closer: 1 problema em 20 (5%) = 1,1' do
      enviados(20).first.lead_activities.create!(account: account, kind: 'apto_devolvido', to_value: 'x', created_at: em(dezembro, 6))

      expect(travel_to(em(fevereiro, 15)) { extrato_de(closer, fevereiro) }[:fator]).to eq(1.1)
    end

    it '1º trimestre da pessoa é 1,0 mesmo com números ruins' do
      reunioes(10)
      no_shows(9, mes: novembro)

      expect(extrato_de(sdr, dezembro)[:fator]).to eq(1.0)
    end

    it 'o fator digitado pelo gestor no trimestre vale no lugar do calculado', :aggregate_failures do
      reunioes(10, mes: dezembro)
      no_shows(6)
      MetaComercial.create!(account: account, user: sdr, papel: 'sdr', mes: fevereiro, meta: 50, fator: 1.0)

      linha = travel_to(em(fevereiro, 15)) { extrato_de(sdr, fevereiro) }
      expect(linha).to include(fator: 1.0)
      expect(linha[:fator_base]).to include(manual: true, calculado: 0.8)
    end

    it 'Closer: cancelamento depois do 1º dia do trimestre novo não entra (o número não depende do dia da leitura)' do
      casos = enviados(20)
      casos.last(4).each { |lead| lead.update_columns(contrato_cancelado_em: em(fevereiro, 20)) } # rubocop:disable Rails/SkipsModelValidations

      expect(travel_to(em(Date.new(2027, 3, 1), 15)) { extrato_de(closer, fevereiro) }[:fator]).to eq(1.1)
    end

    it 'calculado uma vez no trimestre, não muda depois (extrato estável)' do
      reunioes(10, mes: dezembro)
      no_shows(6)
      travel_to(em(fevereiro, 15)) { extrato_de(sdr, fevereiro) }
      reunioes(40, mes: Date.new(2027, 1, 1))

      expect(travel_to(em(Date.new(2027, 3, 1), 15)) { extrato_de(sdr, Date.new(2027, 3, 1)) }[:fator]).to eq(0.8)
    end
  end

  describe 'quanto falta (a cenoura do cartão)' do
    it 'modelo A: quanto falta para a meta do mês' do
      reunioes(30)

      expect(extrato_de(sdr)[:faltam_meta]).to eq(20)
    end

    it 'modelo B: próxima faixa do Programa e a constância até aqui', :aggregate_failures do
      hibrido!
      programa!
      aptos(30, mes: dezembro)

      linha = travel_to(em(dezembro, 20)) { extrato_de(closer, dezembro) }
      expect(linha[:proxima_faixa]).to eq(min: 35, valor: 450.0, faltam: 5)
      expect(linha[:constancia]).to include(min_mes: 25, meses: [{ mes: '2026-12', contagem: 30, ok: true }],
                                            max_problemas: 0.05, taxa: 0.0)
    end

    it 'modelo B: passada a última faixa, quanto falta para o gás' do
      hibrido!
      programa!
      aptos(36, mes: dezembro)

      expect(travel_to(em(dezembro, 20)) { extrato_de(closer, dezembro) }[:proxima_faixa]).to eq(min: 41, valor: 25.0, faltam: 5, gas: true)
    end
  end
end
