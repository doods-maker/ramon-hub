require 'rails_helper'

RSpec.describe Ramon::Fluxos::Retomada do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService); 'Novo' tem stalled_after_days.
  let(:account) { create(:account) }
  let(:novo) { account.lead_stages.find_by(name: 'Novo') }
  let(:contato) { create(:contact, account: account, name: 'Maria da Silva') }
  let(:conversa) { create(:conversation, account: account, contact: contato) }
  let(:lead) { create(:lead, account: account, lead_stage: novo, name: 'Maria da Silva', contact: contato, conversation: conversa) }

  it 'migrado? = só o fluxo próprio da cadência; o desenho do sistema e os das outras migrações não' do
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: 'cadencia'))).to be(true)
    expect(described_class.migrado?(Fluxo.new(origem: 'sistema', sistema_chave: 'cadencia'))).to be(false)
    expect(described_class.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: 'sla_primeira_resposta'))).to be(false)
    expect(Ramon::Fluxos::Migracao.migrado?(Fluxo.new(origem: 'usuario', sistema_chave: 'cadencia'))).to be(true)
  end

  describe 'regras únicas (código e fluxo)' do
    it 'pode retomar: com conversa, sem retomada aberta e a última há 5 dias ou mais' do
      expect(described_class.motivo(lead)).to be_nil
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1, 'ultima_em' => 6.days.ago.iso8601 } })
      expect(described_class.motivo(lead)).to be_nil
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1, 'ultima_em' => 2.days.ago.iso8601 } })
      expect(described_class.motivo(lead)).to include(reason: 'recent_follow_up', days_ago: 2, min_gap_days: 5)
    end

    it 'não pode: sem conversa, ou com tarefa de retomada aberta' do
      expect(described_class.motivo(create(:lead, account: account))).to eq(reason: 'no_conversation')
      create(:lead_task, account: account, lead: lead, kind: 'follow_up', due_at: 1.day.from_now)
      expect(described_class.motivo(lead)).to eq(reason: 'open_follow_up')
    end

    it 'data envenenada no jsonb conta como "nunca" (não derruba o lote)' do
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 2, 'ultima_em' => 'não é data' } })
      expect(described_class.ultima_em(lead)).to be_nil
      expect(described_class.motivo(lead)).to be_nil
      expect(described_class.tentativa(lead)).to eq(3)
    end

    it 'contador que não é objeto no jsonb (a API grava qualquer coisa) conta como vazio' do
      lead.update!(custom_attributes: { 'follow_up' => 'lixo' })
      expect(described_class.tentativa(lead)).to eq(1)
      expect(described_class.ultima_em(lead)).to be_nil
      expect(described_class.motivo(lead)).to be_nil
    end

    it 'tentativas que não é número (lista ou objeto no jsonb) conta como 0' do
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => [1, 2] } })
      expect(described_class.tentativa(lead)).to eq(1)
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => { 'x' => 1 } } })
      expect(described_class.tentativa(lead)).to eq(1)
    end

    it 'registrar conta a tentativa e a data sem apagar as outras chaves do lead' do
      lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 1 }, 'campos' => { 'x' => '1' } })
      expect(described_class.registrar!(lead)).to eq(2)
      attrs = lead.reload.custom_attributes
      expect(attrs['follow_up']['tentativas']).to eq(2)
      expect(Time.zone.parse(attrs['follow_up']['ultima_em'])).to be_within(5.seconds).of(Time.current)
      expect(attrs['campos']).to eq('x' => '1')
    end

    it 'dias parado: dias desde que entrou na etapa (0 sem data)' do
      lead.update_columns(stage_entered_at: 4.days.ago) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.dias_parado(lead)).to eq(4)
      lead.update_columns(stage_entered_at: nil) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.dias_parado(lead)).to eq(0)
    end
  end

  describe 'a chave (RAMON_FLUXO_CADENCIA=on + o fluxo em modo normal)' do
    let!(:fluxo) { described_class.semear(account) }

    it 'semear cria o fluxo parado (modo sombra), ligado, publicado, com o teto do código — uma vez só' do
      expect(fluxo).to have_attributes(origem: 'usuario', sistema_chave: 'cadencia', modo: 'sombra', ativo: true,
                                       limite_dia: 15, gatilho_tipo: 'lead_parado')
      expect(fluxo.versao_publicada.grafo['nos'].first['config']).to eq('tipo' => 'lead_parado', 'hora' => '11:00', 'retomada' => true)
      fluxo.update!(nome: 'Minha cadência')
      expect(described_class.semear(account).id).to eq(fluxo.id)
      expect(fluxo.reload.nome).to eq('Minha cadência')
    end

    it 'só assume com a env ligada e o fluxo normal, ligado, publicado e com o gatilho Lead parado' do
      expect(described_class.assumiu?(account)).to be(false)
      with_modified_env(RAMON_FLUXO_CADENCIA: 'on') do
        expect(described_class.assumiu?(account)).to be(false) # ainda parado
        described_class.mudar_modo!(account, 'normal')
        expect(described_class.assumiu?(account)).to be(true)
        fluxo.update!(ativo: false)
        expect(described_class.assumiu?(account)).to be(false) # desligado na tela devolve ao código
      end
      fluxo.update!(ativo: true)
      expect(described_class.assumiu?(account)).to be(false) # sem a env
    end

    it 'virar para normal sem a env é recusado; voltar devolve ao código; o teto em vigor acompanha' do
      expect { described_class.mudar_modo!(account, 'normal') }.to raise_error(ArgumentError, /RAMON_FLUXO_CADENCIA/)
      with_modified_env(RAMON_FLUXO_CADENCIA: 'on') do
        described_class.mudar_modo!(account, 'normal')
        fluxo.reload.update!(limite_dia: 20)
        expect(described_class.teto(account)).to eq(20)
        expect(described_class.descrever(account)).to include('os FLUXOS fazem a cadência de retomada')
        described_class.mudar_modo!(account, 'sombra')
        expect(described_class.teto(account)).to eq(15)
        expect(described_class.descrever(account)).to include('o CÓDIGO faz a cadência de retomada')
      end
    end
  end

  describe 'ponta a ponta' do
    let(:onze) { Time.find_zone!('America/Sao_Paulo').parse('2026-10-07 11:00') }
    let(:joao) { create(:contact, account: account, name: 'João Pereira') }
    let(:outro) do
      create(:lead, account: account, lead_stage: novo, name: 'João Pereira', contact: joao,
                    conversation: create(:conversation, account: account, contact: joao))
    end
    let!(:fluxo) { described_class.semear(account) }
    let(:reserva) do
      'Oi Maria, tudo bem? Passando pra saber se você ainda tem interesse em olhar o seu caso com a gente. Qualquer coisa, estou por aqui!'
    end

    before do
      [lead, outro].each { |l| l.update_columns(stage_entered_at: onze - 10.days) } # rubocop:disable Rails/SkipsModelValidations
      allow(Ramon::LlmClient).to receive(:complete)
        .and_return(Ramon::LlmClient::Result.new(content: 'Oi [nome], seguimos à disposição.', input_tokens: 1, output_tokens: 1))
    end

    after { %w[2026-10-07 2026-10-10].each { |dia| Redis::Alfred.delete("RAMON::FLUXO_PUSH::#{fluxo.id}::#{dia}") } }

    # O relógio dos fluxos sem o resto: dispara o do dia e anda o que ficou na fila.
    def relogio
      Ramon::Fluxos::Relogio.disparar_do_dia
      andar
    end

    def andar = FluxoExecucao.where(status: 'esperando', retomar_em: ..Time.current).find_each { |e| Ramon::Fluxos::Executor.new(e).avancar! }

    def retomadas(alvo = lead) = alvo.lead_notes.where('body LIKE ?', 'RASCUNHO (revisar antes de enviar) — retomada%')

    describe 'com o fluxo no comando' do
      around { |ex| with_modified_env(RAMON_FLUXO_CADENCIA: 'on') { ex.run } }

      before { described_class.mudar_modo!(account, 'normal') }

      it 'às 11h o fluxo faz a retomada inteira e o código não faz nada' do
        allow(Ramon::FollowUpDraftService).to receive(:new).and_call_original
        travel_to(onze) do
          expect { relogio }.to have_enqueued_job(Ramon::NtfyPushJob).exactly(:once) # 2 leads, 1 push
          Ramon::DailyFollowUpJob.perform_now
        end
        expect(Ramon::FollowUpDraftService).not_to have_received(:new)
        expect(retomadas.pluck(:body)).to eq(["RASCUNHO (revisar antes de enviar) — retomada nº 1:\nOi Maria, seguimos à disposição."])
        expect(retomadas(outro).count).to eq(1)
        expect(lead.lead_tasks.where(kind: 'follow_up').pluck(:title)).to eq(['Retomada nº 1'])
        expect(lead.reload.custom_attributes['follow_up']['tentativas']).to eq(1)
        expect(fluxo.execucoes.where(ensaio: false).pluck(:status)).to eq(%w[concluida concluida])
      end

      it 'a virada não repete: respeita a retomada recente e a tarefa aberta que o código deixou' do
        lead.update!(custom_attributes: { 'follow_up' => { 'tentativas' => 2, 'ultima_em' => (onze - 2.days).iso8601 } })
        create(:lead_task, account: account, lead: outro, kind: 'follow_up', due_at: onze + 1.hour)
        travel_to(onze) { relogio }
        expect(retomadas.count + retomadas(outro).count).to eq(0)
        travel_to(onze + 3.days) { relogio }
        expect(retomadas.last.body).to start_with('RASCUNHO (revisar antes de enviar) — retomada nº 3:')
        expect(retomadas(outro).count).to eq(0) # a tarefa do código segue aberta
      end

      it 'o botão Preparar retomada roda o fluxo para o lead, sem o teto; o clique duplo não gera 2' do
        fluxo.reload.update!(limite_dia: 1)
        travel_to(onze - 2.hours) do
          Ramon::FollowUpDraftJob.perform_now(outro.id) # gasta o limite do dia
          2.times { Ramon::FollowUpDraftJob.perform_now(lead.id) }
          andar
          Ramon::FollowUpDraftJob.perform_now(lead.id) # já tem retomada aberta: nada
          andar
        end
        expect(retomadas.count).to eq(1)
        expect(retomadas(outro).count).to eq(1)
        expect(fluxo.execucoes.where(alvo: lead).count).to eq(1)
      end

      it 'IA fora do ar: entra o texto fixo de reserva e a retomada segue (contador e tarefa)' do
        allow(Ramon::LlmClient).to receive(:complete).and_raise(Ramon::LlmClient::TransientError, 'timeout')
        travel_to(onze) { relogio }
        expect(retomadas.last.body).to eq("RASCUNHO (revisar antes de enviar) — retomada nº 1:\n#{reserva}")
        expect(lead.lead_tasks.where(kind: 'follow_up').count).to eq(1)
        expect(fluxo.execucoes.where(status: 'falhou').count).to eq(0)
      end
    end

    describe 'com o código no comando' do
      it 'fluxo em modo normal mas sem a env: o relógio nem dispara o fluxo; o lote e o botão são do código' do
        with_modified_env(RAMON_FLUXO_CADENCIA: 'on') { described_class.mudar_modo!(account, 'normal') }
        travel_to(onze) do
          Ramon::FollowUpDraftJob.perform_now(lead.id) # o botão: o código faz na hora
          relogio
          Ramon::DailyFollowUpJob.perform_now
        end
        expect(fluxo.execucoes.count).to eq(0)
        expect(retomadas.count + retomadas(outro).count).to eq(2) # o código fez: o botão (Maria) e o lote (João)
        expect(fluxo.reload.ultimo_disparo_em).to be_present # o dia ficou reivindicado: virar depois das 11h não roda 2º lote
      end

      it 'fluxo desligado na tela: o código faz o lote e reivindica o dia do fluxo — religar depois das 11h não roda 2º lote' do
        tarefa = create(:lead_task, account: account, lead: outro, kind: 'follow_up', due_at: onze + 1.hour)
        with_modified_env(RAMON_FLUXO_CADENCIA: 'on') do
          described_class.mudar_modo!(account, 'normal')
          fluxo.reload.update!(ativo: false) # desligado na tela: quem faz é o código
          travel_to(onze) { Ramon::DailyFollowUpJob.perform_now }
          tarefa.update!(completed_at: onze) # o João fica livre para retomada depois do lote
          fluxo.update!(ativo: true) # chave inteira de novo, às 11h30
          travel_to(onze + 30.minutes) { relogio }
        end
        expect(retomadas.count).to eq(1) # o lote do código (a Maria)
        expect(fluxo.reload.ultimo_disparo_em).to be_within(1.second).of(onze)
        expect(fluxo.execucoes.count + retomadas(outro).count).to eq(0) # sem o dia reivindicado, o relógio retomaria o João
      end
    end
  end
end
