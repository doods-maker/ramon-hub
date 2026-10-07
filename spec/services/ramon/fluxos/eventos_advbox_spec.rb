require 'rails_helper'

RSpec.describe Ramon::Fluxos::EventosAdvbox do
  # A conta seeda o funil no after_create (Novo ... Fechado is_won / Perdido is_lost).
  let(:account) { create(:account) }
  let(:lead) { novo_lead('+5548999000001') }

  def novo_lead(fone)
    contato = create(:contact, account: account, phone_number: fone)
    create(:lead, account: account, lead_stage: account.lead_stages.order(:position).first, contact: contato, name: 'Maria da Silva')
  end

  def migrado(modo: 'sombra')
    fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox', 'cancelar_se_sair_da_etapa' => false },
                                          ['registrar_atividade', { 'texto' => 'pelo fluxo: {texto}' }]),
                    origem: 'usuario', sistema_chave: 'eventos_advbox', modo: modo)
  end

  def atividades(kinds) = lead.lead_activities.where(kind: kinds).order(:id).pluck(:kind)

  describe 'a decisão é do evento (lida uma vez)' do
    it 'código no comando (padrão): o código faz; o fluxo migrado só ensaia, antes, na hora' do
      fluxo = migrado
      described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA')
      expect(atividades(%w[advbox_marco fluxo])).to eq(['advbox_marco'])
      expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[true, 'concluida']])
    end

    it 'fluxo no comando: só o fluxo age, na hora (dentro do job do ADVBOX); o código não faz nada' do
      fluxo = migrado(modo: 'normal')
      with_modified_env(RAMON_FLUXO_EVENTOS_ADVBOX: 'on') { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(atividades(%w[advbox_marco fluxo])).to eq(['fluxo'])
      expect(lead.lead_activities.find_by(kind: 'fluxo').to_value).to eq('pelo fluxo: SENTENCA PROFERIDA')
      expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
    end

    it 'fluxo no comando mas ocupado com o mesmo lead (execução viva): o código faz este evento — nada se perde, nada em dobro' do
      fluxo = migrado(modo: 'normal')
      fluxo.execucoes.create!(account: account, alvo: lead, status: 'esperando', retomar_em: 5.minutes.from_now)
      with_modified_env(RAMON_FLUXO_EVENTOS_ADVBOX: 'on') { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(atividades(%w[advbox_marco fluxo])).to eq(['advbox_marco'])
      expect(fluxo.execucoes.count).to eq(1) # a viva; este evento não criou outra
    end

    it 'fluxo no comando mas o filtro de regras do gatilho não pega o evento: o código faz (o filtro não desliga efeito)' do
      fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox', 'regras' => ['exito'] }, ['parar', {}]),
                              origem: 'usuario', sistema_chave: 'eventos_advbox', modo: 'normal')
      with_modified_env(RAMON_FLUXO_EVENTOS_ADVBOX: 'on') { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(atividades(%w[advbox_marco fluxo])).to eq(['advbox_marco'])
      expect(fluxo.execucoes.count).to eq(0)
    end

    it 'os fluxos comuns de evento do ADVBOX seguem como sempre: depois, sem a decisão, com as variáveis do código' do
      comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox' }, ['registrar_atividade', { 'texto' => 'comum' }]))
      travel_to(Time.zone.parse('2026-10-07 13:00:00 UTC')) { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(comum.execucoes.sole.contexto['gatilho'])
        .to eq('regra' => 'marco', 'texto' => 'SENTENCA PROFERIDA', 'primeiro_nome' => 'Maria', 'hoje' => '07/10/2026')
    end
  end

  describe 'o fluxo faz o mesmo que o código, regra a regra (atividades, tarefas, rascunhos, etapa)' do
    let(:pelo_codigo) { novo_lead('+5548999000011') }
    let(:pelo_fluxo) { novo_lead('+5548999000012') }

    # o que fica no lead; o dossiê muda de lead para lead (link da ficha) — só o começo conta
    def rastro(alvo)
      alvo.reload
      { atividades: alvo.lead_activities.where.not(kind: 'created').order(:id).pluck(:kind, :to_value),
        tarefas: alvo.lead_tasks.order(:id).pluck(:kind, :title, :completed_at).map { |k, t, feita| [k, t, feita.present?] },
        notas: alvo.lead_notes.order(:id).pluck(:body).map { |b| b.start_with?('📋') ? '📋 DOSSIÊ' : b },
        etapa: alvo.lead_stage.name }
    end

    def execucoes_de(alvo) = FluxoExecucao.where(alvo: alvo, ensaio: false).count

    { 'contrato_fechado' => 'CONTRATO FECHADO', 'requerimento_protocolado' => 'REQUERIMENTO PROTOCOLADO',
      'indeferimento' => 'NEGADO / AVISAR CLIENTE', 'decisao' => 'DECISAO PROFERIDA', 'exigencia' => 'CARTA DE EXIGENCIAS',
      'reativacao_futura' => 'BENEFICIO FUTURO / ANOTAR NA AGENDA', 'exito' => 'PAGAMENTO RECEBIDO / PAGAR CLIENTE',
      'marco' => 'SENTENCA PROFERIDA', 'concessao' => 'BENEFICIO CONCEDIDO / IMPLANTACAO',
      'arquivado' => 'ARQUIVADO/ENCERRADO' }.each do |regra, nome|
      it "#{regra}: o lead fica igual pelos dois caminhos — e cada lado decidiu 1 vez" do
        allow(Ramon::AdvboxEventRegras).to receive(:new).and_call_original
        allow(Ramon::Fluxos::LeadGanho).to receive(:pelo_codigo).and_call_original
        [pelo_codigo, pelo_fluxo].each { |l| l.lead_tasks.create!(account: account, kind: 'other', title: 'Aberta', due_at: 1.day.from_now) }
        perform_enqueued_jobs { described_class.processar(pelo_codigo, regra, nome) } # código no comando (sem env, sem fluxo)
        with_modified_env(RAMON_FLUXO_EVENTOS_ADVBOX: 'on') do
          Ramon::Fluxos::Migracao.semear(account, 'eventos_advbox')
          Ramon::Fluxos::Migracao.mudar_modo!(account, 'eventos_advbox', 'normal')
          perform_enqueued_jobs { described_class.processar(pelo_fluxo, regra, nome) }
        end
        expect(rastro(pelo_fluxo)).to eq(rastro(pelo_codigo))
        # as travas (NPS 1 vez, dossiê 5 min) escondem dobra nos efeitos: contar QUEM decidiu fazer
        expect(Ramon::AdvboxEventRegras).to have_received(:new).once # só o lado do código
        expect([execucoes_de(pelo_codigo), execucoes_de(pelo_fluxo)]).to eq([0, 1])
        # o lead ganho (sem a chave dele) é do código: 1 vez por lead, só no contrato fechado
        expect(Ramon::Fluxos::LeadGanho).to have_received(:pelo_codigo).exactly(regra == 'contrato_fechado' ? 2 : 0).times
      end
    end
  end

  describe 'contrato fechado nunca faz o Lead ganho em dobro (nem deixa de fazer)' do
    [[false, false], [true, false], [false, true], [true, true]].each do |advbox_flui, ganho_flui|
      it "eventos pelo #{advbox_flui ? 'fluxo' : 'código'}, lead ganho pelo #{ganho_flui ? 'fluxo' : 'código'}: 1 de cada" do
        allow(Ramon::AdvboxClient).to receive_messages(create_customer: { 'customers_id' => 11 },
                                                        create_lawsuit: { 'lawsuits_id' => 22 }, create_post: { 'posts_id' => 33 })
        allow(Ramon::Fluxos::LeadGanho).to receive(:pelo_codigo).and_call_original
        allow(Ramon::AdvboxEventRegras).to receive(:new).and_call_original
        with_modified_env(ADVBOX_API_TOKEN: 'tok', RAMON_FLUXO_EVENTOS_ADVBOX: 'on', RAMON_FLUXO_LEAD_GANHO: 'on') do
          %w[eventos_advbox lead_ganho].each { |grupo| Ramon::Fluxos::Migracao.semear(account, grupo) }
          Ramon::Fluxos::Migracao.mudar_modo!(account, 'eventos_advbox', 'normal') if advbox_flui
          Ramon::Fluxos::Migracao.mudar_modo!(account, 'lead_ganho', 'normal') if ganho_flui
          perform_enqueued_jobs { described_class.processar(lead, 'contrato_fechado', 'CONTRATO FECHADO') }
        end
        notas = lead.reload.lead_notes.pluck(:body)
        # as travas (5 min, 1 vez, sincronizado_em) escondem dobra nos efeitos: contar QUEM decidiu fazer
        expect(Ramon::AdvboxEventRegras).to have_received(:new).exactly(advbox_flui ? 0 : 1).times
        expect(Ramon::Fluxos::LeadGanho).to have_received(:pelo_codigo).exactly(ganho_flui ? 0 : 1).times
        expect(FluxoExecucao.where(alvo: lead, ensaio: false).count).to eq([advbox_flui, ganho_flui].count(true))
        expect([notas.count { |b| b.start_with?('📋') }, notas.count { |b| b.include?('pesquisa NPS') }]).to eq([1, 1])
        expect(Ramon::AdvboxClient).to have_received(:create_customer).once
        expect(lead.lead_activities.where(kind: 'advbox_contrato_fechado').count).to eq(1)
      end
    end
  end

  it 'primeiro nome como o código escreve nos rascunhos: lead sem nome vira "cliente"' do
    expect([described_class.primeiro_nome(lead), described_class.primeiro_nome(Lead.new(name: nil))]).to eq(%w[Maria cliente])
  end
end
