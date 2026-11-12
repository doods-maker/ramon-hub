require 'rails_helper'

RSpec.describe Ramon::ContratoApto do
  let(:account) { create(:account) }
  let(:won_stage) { account.lead_stages.find_by(is_won: true) }
  let(:open_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Gestor') }
  let(:rafaela) { create(:user, account: account, role: :agent, name: 'Rafaela') }
  let(:tamires) { create(:user, account: account, role: :agent, name: 'Tamires') }
  let(:outra) { create(:user, account: account, role: :agent, name: 'Crisleine') }
  let(:closer) { create(:user, account: account, role: :agent, name: 'Caio Closer') }
  let(:tese) { create(:thesis, account: account, name: 'Tese do apto', validador_ids: [rafaela.id, tamires.id]) }
  # sexta-feira, 13/11/2026, 10h em São Paulo; 20/11 é feriado (Consciência Negra)
  let(:sexta) { Time.find_zone('America/Sao_Paulo').local(2026, 11, 13, 10) }

  before { admin }

  # assinado: false = ganho sem o selo do ZapSign (arrasto manual no Kanban, contrato em papel)
  def limpo(carimbo: sexta, thesis: tese, assinado: true, custom_attributes: {}, **attrs)
    custom_attributes = custom_attributes.merge('zapsign' => { 'status' => 'signed' }) if assinado
    attrs = attrs.merge(custom_attributes: custom_attributes)
    create(:lead, account: account, lead_stage: won_stage, thesis: thesis, closer: closer, **attrs).tap do |lead|
      lead.update_columns(contrato_limpo_em: carimbo) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def aguardando(**attrs)
    limpo(**attrs).tap { |lead| lead.update_columns(validacao_desde: lead.contrato_limpo_em) } # rubocop:disable Rails/SkipsModelValidations
  end

  def avisos_de(user) = user.notifications.where(notification_type: 'ramon_fluxo_aviso')

  describe '.validadores / .pode_validar?' do
    it 'são os advogados da tese; o admin também pode validar', :aggregate_failures do
      lead = aguardando

      expect(described_class.validadores(lead)).to contain_exactly(rafaela.id, tamires.id)
      expect(described_class.pode_validar?(lead, rafaela)).to be(true)
      expect(described_class.pode_validar?(lead, admin)).to be(true)
      expect(described_class.pode_validar?(lead, outra)).to be(false)
      expect(described_class.pode_validar?(lead, closer)).to be(false)
    end

    it 'o advogado designado no lead vale no lugar da tese (tese sem advogado fixo, ex.: IR)' do
      lead = aguardando(validador_id: outra.id)

      expect(described_class.validadores(lead)).to eq([outra.id])
    end

    it 'tese sem advogado e lead sem designado: os administradores' do
      lead = aguardando(thesis: create(:thesis, account: account, name: 'Tese sem advogado'))

      expect(described_class.validadores(lead)).to eq([admin.id])
    end
  end

  describe '.prazo' do
    it 'é de 5 dias úteis, sem fim de semana nem feriado' do
      # conta do dia seguinte: seg 16, ter 17, qua 18, qui 19, (sex 20 feriado), seg 23 — vence no fim do dia
      expect(described_class.prazo(aguardando)).to eq(Time.find_zone('America/Sao_Paulo').local(2026, 11, 23, 23, 59, 59))
    end

    it 'só existe enquanto aguarda validação' do
      expect(described_class.prazo(limpo)).to be_nil
    end

    it 'não existe sem assinatura conferida no ZapSign; o painel recebe o motivo', :aggregate_failures do
      lead = aguardando(assinado: false)

      expect(described_class.prazo(lead)).to be_nil
      expect(described_class.dados(lead)).to include(apto_situacao: 'aguardando', apto_prazo: nil, assinatura_conferida: false)
      expect(described_class.dados(aguardando)).to include(assinatura_conferida: true)
    end
  end

  describe '.rodar!' do
    it 'contrato limpo entra na fila com o relógio no carimbo e avisa quem valida', :aggregate_failures do
      lead = limpo

      described_class.rodar!(sexta + 1.hour)

      expect(lead.reload.validacao_desde).to eq(sexta)
      expect(described_class.situacao(lead)).to eq('aguardando')
      expect(avisos_de(rafaela).count).to eq(1)
      expect(avisos_de(tamires).count).to eq(1)
      expect(avisos_de(outra).count).to eq(0)
    end

    it 'contrato limpo de antes da regra não entra na fila (o estoque não vira apto por prazo no deploy)' do
      lead = limpo(carimbo: Time.find_zone('America/Sao_Paulo').local(2026, 10, 20, 10))

      described_class.rodar!(sexta)

      expect(lead.reload).to have_attributes(validacao_desde: nil, apto_em: nil)
    end

    it 'tese sem advogado fixo: o responsável do processo no ADVBOX vira o validador ao entrar na fila', :aggregate_failures do
      sem_fixo = create(:thesis, account: account, name: 'Isenção de IR (teste)')
      lead = limpo(thesis: sem_fixo, custom_attributes: { 'advbox' => { 'lawsuits_id' => 77 } })
      allow(Ramon::AdvboxClient).to receive(:lawsuit).with(77).and_return('id' => 77, 'responsible_id' => 5)
      allow(Ramon::AdvboxClient).to receive(:settings).and_return('users' => [{ 'id' => 5, 'email' => outra.email.upcase }])

      described_class.rodar!(sexta + 1.hour)

      expect(lead.reload.validador_id).to eq(outra.id)
      expect(avisos_de(outra).count).to eq(1)
    end

    it 'ADVBOX fora do ar não trava a fila: ficam os administradores' do
      lead = limpo(thesis: create(:thesis, account: account, name: 'Tese ADVBOX fora'), custom_attributes: { 'advbox' => { 'lawsuits_id' => 77 } })
      allow(Ramon::AdvboxClient).to receive(:lawsuit).and_raise(Ramon::AdvboxClient::UnavailableError, 'fora')

      described_class.rodar!(sexta + 1.hour)

      expect(described_class.validadores(lead.reload)).to eq([admin.id])
    end

    it 'não avisa de novo quem já está na fila' do
      limpo
      described_class.rodar!(sexta + 1.hour)

      expect { described_class.rodar!(sexta + 2.hours) }.not_to(change { avisos_de(rafaela).count })
    end

    it 'vencido o prazo sem resposta, fica apto sozinho na hora do prazo e avisa o Closer', :aggregate_failures do
      lead = aguardando
      prazo = described_class.prazo(lead)

      described_class.rodar!(prazo - 1.minute)
      expect(lead.reload.apto_em).to be_nil

      described_class.rodar!(prazo + 1.hour)
      expect(lead.reload).to have_attributes(apto_em: prazo, apto_por_id: nil)
      expect(described_class.situacao(lead)).to eq('apto_por_prazo')
      expect(avisos_de(closer).count).to eq(1)
    end

    it 'sem assinatura conferida no ZapSign o prazo vencido não vira apto: espera o advogado', :aggregate_failures do
      lead = aguardando(assinado: false)

      described_class.rodar!(sexta + 30.days)

      expect(lead.reload.apto_em).to be_nil
      expect(described_class.situacao(lead)).to eq('aguardando')
      expect(lead.lead_activities.where(kind: 'apto_por_prazo')).to be_empty
      expect(avisos_de(closer).count).to eq(0)
    end

    it 'documento recusado no ZapSign também não fica apto por prazo' do
      lead = aguardando(assinado: false, custom_attributes: { 'zapsign' => { 'status' => 'refused' } })

      described_class.rodar!(sexta + 30.days)

      expect(lead.reload.apto_em).to be_nil
    end

    it 'contrato limpo antes da regra da assinatura (estoque da fila) segue a regra antiga: apto por prazo sem o selo', :aggregate_failures do
      lead = aguardando(assinado: false, carimbo: Time.find_zone('America/Sao_Paulo').local(2026, 11, 11, 10))

      expect(described_class.dados(lead)).to include(assinatura_conferida: true) # sem o aviso no painel
      described_class.rodar!(sexta + 30.days)

      expect(described_class.situacao(lead.reload)).to eq('apto_por_prazo')
    end

    it 'devolvido não fica apto por prazo' do
      lead = aguardando(devolvido_em: sexta + 1.day, devolvido_motivo: 'Falta o laudo')

      described_class.rodar!(sexta + 30.days)

      expect(lead.reload.apto_em).to be_nil
    end
  end

  describe '.validar! / .devolver! / .reenviar!' do
    it 'o advogado da tese valida: apto com data e quem validou; o Closer é avisado', :aggregate_failures do
      lead = aguardando

      travel_to(sexta + 1.day) { described_class.validar!(lead, rafaela) }

      expect(lead.reload).to have_attributes(apto_em: sexta + 1.day, apto_por_id: rafaela.id)
      expect(described_class.situacao(lead)).to eq('apto')
      expect(avisos_de(closer).count).to eq(1)
    end

    it 'sem assinatura conferida o advogado ainda valida na mão (contrato em papel)', :aggregate_failures do
      lead = aguardando(assinado: false)

      described_class.validar!(lead, rafaela)

      expect(described_class.situacao(lead.reload)).to eq('apto')
      expect(described_class.validar_lote!(account, rafaela, [aguardando(assinado: false).id])[:recusados]).to be_empty
    end

    it 'quem não é da tese nem admin não valida' do
      expect { described_class.validar!(aguardando, outra) }.to raise_error(described_class::Proibido)
    end

    it 'devolver exige motivo, grava quem devolveu e avisa o Closer', :aggregate_failures do
      lead = aguardando

      expect { described_class.devolver!(lead, rafaela, ' ') }.to raise_error(described_class::Invalido)
      described_class.devolver!(lead, rafaela, 'Falta o laudo')

      expect(lead.reload).to have_attributes(devolvido_por_id: rafaela.id, devolvido_motivo: 'Falta o laudo', apto_em: nil)
      expect(lead.lead_activities.find_by(kind: 'apto_devolvido')).to have_attributes(user_id: rafaela.id, to_value: 'Falta o laudo')
      expect(described_class.situacao(lead)).to eq('devolvido')
      expect(avisos_de(closer).count).to eq(1)
    end

    it 'o Closer corrige e reenvia: relógio novo e quem valida é avisado de novo', :aggregate_failures do
      lead = aguardando
      described_class.devolver!(lead, rafaela, 'Falta o laudo')

      travel_to(sexta + 3.days) { described_class.reenviar!(lead, closer) }

      expect(lead.reload).to have_attributes(validacao_desde: sexta + 3.days, devolvido_em: nil, devolvido_motivo: nil)
      expect(described_class.situacao(lead)).to eq('aguardando')
      expect(avisos_de(rafaela).count).to eq(1)
    end

    it 'só valida o que está aguardando' do
      lead = aguardando
      described_class.validar!(lead, rafaela)

      expect { described_class.validar!(lead.reload, tamires) }.to raise_error(described_class::Invalido)
    end
  end

  describe '.designar!' do
    it 'só o admin designa o advogado do lead', :aggregate_failures do
      lead = aguardando

      expect { described_class.designar!(lead, rafaela, outra) }.to raise_error(described_class::Proibido)
      described_class.designar!(lead, admin, outra)

      expect(described_class.validadores(lead.reload)).to eq([outra.id])
    end
  end

  describe '.fila / .validar_lote!' do
    it 'a fila de cada advogado tem só os casos dele; o admin vê todos', :aggregate_failures do
      meu = aguardando
      de_outra = aguardando(validador_id: outra.id)

      expect(described_class.fila(account, rafaela)).to eq([meu])
      expect(described_class.fila(account, admin)).to contain_exactly(meu, de_outra)
    end

    it 'valida em lote só o que a pessoa pode validar e diz o que ficou de fora', :aggregate_failures do
      meu = aguardando
      de_outra = aguardando(validador_id: outra.id)

      resultado = described_class.validar_lote!(account, rafaela, [meu.id, de_outra.id])

      expect(resultado).to eq(validados: [meu.id], recusados: [de_outra.id])
      expect(described_class.situacao(meu.reload)).to eq('apto')
      expect(described_class.situacao(de_outra.reload)).to eq('aguardando')
    end
  end

  describe 'cancelamento (sair de Fechado)' do
    it 'antes do apto tira da fila' do
      lead = aguardando

      lead.update!(lead_stage: open_stage)

      expect(lead.reload).to have_attributes(contrato_limpo_em: nil, validacao_desde: nil, contrato_cancelado_em: be_present)
    end

    it 'depois do apto a comissão é devida: o apto fica' do
      lead = aguardando
      described_class.validar!(lead, rafaela)

      lead.reload.update!(lead_stage: open_stage)

      expect(lead.reload).to have_attributes(apto_em: be_present, contrato_cancelado_em: be_present)
    end

    it 'voltou a fechar logo depois (arrasto por engano): o cancelamento deixa de valer' do
      lead = aguardando
      described_class.validar!(lead, rafaela)
      lead.reload.update!(lead_stage: open_stage)

      lead.reload.update!(lead_stage: won_stage)

      expect(lead.reload).to have_attributes(apto_em: be_present, contrato_cancelado_em: nil)
    end

    it 'voltou a fechar dias depois: o cancelamento fica (já pode ter entrado na apuração)' do
      lead = aguardando
      described_class.validar!(lead, rafaela)
      lead.reload.update!(lead_stage: open_stage)
      lead.update_columns(contrato_cancelado_em: 2.days.ago) # rubocop:disable Rails/SkipsModelValidations

      lead.reload.update!(lead_stage: won_stage)

      expect(lead.reload.contrato_cancelado_em).to be_present
    end
  end
end
