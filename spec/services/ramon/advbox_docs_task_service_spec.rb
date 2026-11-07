require 'rails_helper'

# ANÁLISE DO CASO (spec Etapa Documentos §8): uma tarefa por caso, no processo que o Ganho abriu, com o caminho da pasta da tese
# nas notas; ADVBOX fora do ar → o retry do job cria uma vez só (o id é gravado assim que a tarefa nasce).
RSpec.describe Ramon::AdvboxDocsTaskService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Maria das Dores', cpf: '529.982.247-25') }
  let(:tese) { create(:thesis, account: account, name: 'Tese de teste (B99)') }
  let(:won_stage) { create(:lead_stage, account: account, is_won: true) }
  let(:advbox) { { 'lawsuits_id' => 999 } }
  let(:lead) do
    create(:lead, account: account, contact: contact, thesis: tese, lead_stage: won_stage, won_at: Time.zone.local(2026, 11, 3, 10),
                  custom_attributes: { 'advbox' => advbox, 'outro' => 'fica' })
  end
  let(:pasta) { 'Clientes\Maria das Dores — 529.982.247-25\Tese de teste (B99) – 11.26 — COMPLETO\\' }

  around { |example| with_modified_env(ADVBOX_API_TOKEN: 'tok') { example.run } }

  describe '#analise_do_caso' do
    it 'cria a tarefa ANÁLISE DO CASO para o Eduardo, com a pasta da tese, e guarda o id no lead', :aggregate_failures do
      expect(Ramon::AdvboxClient).to receive(:create_post)
        .with(hash_including(tasks_id: '8745386', from: '266778', guests: [266_778], lawsuits_id: '999',
                             comments: a_string_including(pasta, "Lead ##{lead.id}")))
        .and_return({ 'posts_id' => 777 })

      expect(described_class.new(lead).analise_do_caso).to eq(:criada)
      expect(lead.reload.custom_attributes).to eq('advbox' => { 'lawsuits_id' => 999, 'analise_posts_id' => 777 }, 'outro' => 'fica')
    end

    context 'when a tarefa já foi criada' do
      let(:advbox) { { 'lawsuits_id' => 999, 'analise_posts_id' => 777 } }

      it 'não cria outra' do
        expect(Ramon::AdvboxClient).not_to receive(:create_post)
        expect(described_class.new(lead).analise_do_caso).to eq(:ja_criada)
      end
    end

    context 'when o Ganho não abriu o caso no ADVBOX (sem lawsuits_id)' do
      let(:advbox) { { 'erro' => 'recusou' } }

      it 'não cria nada e diz o motivo' do
        expect(Ramon::AdvboxClient).not_to receive(:create_post)
        expect(described_class.new(lead).analise_do_caso).to eq(:sem_caso)
      end
    end

    it 'ADVBOX fora do ar: sobe o erro sem gravar nada, e o retry cria a tarefa uma vez só', :aggregate_failures do
      allow(Ramon::AdvboxClient).to receive(:create_post).and_raise(Ramon::AdvboxClient::UnavailableError)
      expect { described_class.new(lead).analise_do_caso }.to raise_error(Ramon::AdvboxClient::UnavailableError)
      expect(lead.reload.custom_attributes['advbox']).not_to have_key('analise_posts_id')

      allow(Ramon::AdvboxClient).to receive(:create_post).and_return({ 'posts_id' => 777 })
      expect(described_class.new(lead).analise_do_caso).to eq(:criada)
      expect(described_class.new(lead.reload).analise_do_caso).to eq(:ja_criada)
      expect(Ramon::AdvboxClient).to have_received(:create_post).twice # a que falhou + a do retry
    end

    # Review do PR 6, item 1: merge_advbox, merge_drive e o DocMatch regravam o custom_attributes inteiro de uma cópia velha.
    it 'a marca sobrevive a quem regrava o custom_attributes inteiro a partir de uma cópia lida antes dela', :aggregate_failures do
      copia_velha = Lead.find(lead.id)
      allow(Ramon::AdvboxClient).to receive(:create_post).and_return({ 'posts_id' => 777 })
      described_class.new(lead).analise_do_caso

      copia_velha.update!(custom_attributes: copia_velha.custom_attributes.merge('drive' => { 'concluido_em' => 'agora' }))

      expect(lead.reload.custom_attributes['advbox']).to eq('lawsuits_id' => 999, 'analise_posts_id' => 777)
      expect(lead.custom_attributes['drive']).to eq('concluido_em' => 'agora')
      expect(described_class.new(lead).analise_do_caso).to eq(:ja_criada)
    end

    # Review do PR 6, item 2: quem serializa as chamadas juntas é o lock do lead; o Redis fora do ar não perde a tarefa.
    it 'não depende do Redis' do
      allow(Redis::Alfred).to receive(:set).and_raise(Redis::CannotConnectError)
      allow(Ramon::AdvboxClient).to receive(:create_post).and_return({ 'posts_id' => 777 })
      expect(described_class.new(lead).analise_do_caso).to eq(:criada)
    end

    it 'ADVBOX recusou (4xx): não grava e diz o motivo' do
      allow(Ramon::AdvboxClient).to receive(:create_post).and_raise(Ramon::AdvboxClient::RequestError.new(422, 'inválido'))
      expect(described_class.new(lead).analise_do_caso).to eq(:recusada)
    end
  end

  describe '#perform (tarefa de upload da controller)' do
    it 'cita a pasta da tese, não a do cliente' do
      with_modified_env(RAMON_ADVBOX_CONTROLLER_ID: '111', RAMON_ADVBOX_DOCS_TASK_ID: '222') do
        expect(Ramon::AdvboxClient).to receive(:create_post).with(hash_including(comments: a_string_including(pasta)))
                                                            .and_return({ 'posts_id' => 555 })
        described_class.new(lead).perform
      end
    end
  end
end
