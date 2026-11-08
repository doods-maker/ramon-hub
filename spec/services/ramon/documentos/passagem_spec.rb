require 'rails_helper'

# Checklist completo em Documentos → Jurídico (spec Etapa Documentos §8): o lead anda, a ANÁLISE DO CASO nasce no ADVBOX (uma por
# caso), o encerramento aprovado sai na janela e a conversa sai da IA. Data relativa (próxima segunda, 10h em SP), como a cobrança.
RSpec.describe Ramon::Documentos::Passagem do
  let(:segunda) { Time.find_zone!('America/Sao_Paulo').now.next_occurring(:monday).change(hour: 10) }
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:etapas) { Ramon::EtapasPosVenda.criar!(account) }
  let(:documentos) { etapas.first }
  let(:juridico) { etapas.last }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
  end
  let(:conversa) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:tese) { create(:thesis, account: account, name: 'Tese Spec Passagem') }
  let!(:item) { create(:thesis_item, thesis: tese, section: 'documento', title: 'CNIS completo') }
  let(:contato) { create(:contact, account: account, name: 'Maria da Silva', cpf: '529.982.247-25') }
  let(:lead) { create(:lead, account: account, thesis: tese, contact: contato, name: 'Maria da Silva') }
  let(:advbox) { { 'lawsuits_id' => 999 } }

  around do |exemplo|
    travel_to(segunda) { with_modified_env(RAMON_ETAPA_DOCUMENTOS: 'on', ADVBOX_API_TOKEN: 'tok') { exemplo.run } }
  end

  before do
    allow(Ramon::NtfyPushJob).to receive(:perform_later)
    allow(Ramon::AdvboxClient).to receive(:create_post).and_return({ 'posts_id' => 777 })
  end

  def completo_em(etapa)
    lead.update_columns(conversation_id: conversa.id, lead_stage_id: etapa.id, won_at: 1.day.ago, docs_completos_em: Time.current, # rubocop:disable Rails/SkipsModelValidations
                        custom_attributes: { 'doc_status' => { item.id.to_s => 'recebido' }, 'advbox' => advbox })
  end

  def cliente_escreveu(atras)
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming, created_at: atras.ago)
  end

  def enviadas = conversa.messages.outgoing.where(private: false)
  def historico = lead.lead_activities.where(kind: 'documentos').pluck(:to_value)
  def avisos = Notification.where(primary_actor: lead, notification_type: 'ramon_fluxo_aviso')

  # O texto aprovado pelo Eduardo em 07/11 (seção 3.5), literal.
  def encerramento
    'Recebemos tudo, Maria! Muito obrigado pela paciência. Agora o seu caso segue para a nossa equipe jurídica, que vai estudar ' \
      'cada detalhe. Qualquer novidade, a gente te avisa por aqui.'
  end

  context 'when o lead está em Documentos com o checklist completo' do
    before do
      completo_em(documentos)
      cliente_escreveu(1.hour)
    end

    it 'vai ao Jurídico, nasce a ANÁLISE DO CASO, sai o encerramento e a conversa sai da IA', :aggregate_failures do
      described_class.call(lead)

      expect(lead.reload.lead_stage).to eq(juridico)
      expect(Ramon::AdvboxClient).to have_received(:create_post).with(hash_including(tasks_id: '8745386', lawsuits_id: '999')).once
      expect(lead.custom_attributes.dig('advbox', 'analise_posts_id')).to eq(777)
      expect(enviadas.pluck(:content)).to eq([encerramento])
      expect(conversa.reload).to be_open
      expect(historico).to include(a_string_including('encerramento'), a_string_including('ANÁLISE DO CASO'))
      expect(avisos).to be_empty
    end

    # Teste ponta a ponta de 07/11: a IA tinha passado para a equipe e o encerramento não saiu. Decisão do Eduardo: sai mesmo assim.
    it 'conversa já com uma pessoa (aberta, com responsável): o encerramento sai do mesmo jeito', :aggregate_failures do
      conversa.update!(status: :open, assignee: admin)

      described_class.call(lead)

      expect(enviadas.pluck(:content)).to eq([encerramento])
      expect(lead.reload.lead_stage).to eq(juridico)
    end

    it 'rodar de novo não repete nada' do
      2.times { described_class.call(lead.reload) }

      expect(enviadas.count).to eq(1)
      expect(Ramon::AdvboxClient).to have_received(:create_post).once
    end

    it 'janela de 24 h fechada: o encerramento não sai (e fica no histórico); o resto acontece', :aggregate_failures do
      conversa.messages.incoming.update_all(created_at: 30.hours.ago) # rubocop:disable Rails/SkipsModelValidations

      described_class.call(lead)

      expect(enviadas).to be_empty
      expect(historico).to include(a_string_including('encerramento não saiu'))
      expect(lead.reload.lead_stage).to eq(juridico)
      expect(Ramon::AdvboxClient).to have_received(:create_post).once
    end

    it 'encerramento sem aprovação (texto vazio): nada vai ao cliente; o resto acontece (Review Focus 5)', :aggregate_failures do
      config = Ramon::Documentos::Envio::CONFIG
      stub_const('Ramon::Documentos::Envio::CONFIG', config.merge('mensagens' => config['mensagens'].merge('encerramento' => nil)))

      described_class.call(lead)

      expect(enviadas).to be_empty
      expect(lead.reload.lead_stage).to eq(juridico)
      expect(conversa.reload).to be_open
      expect(Ramon::AdvboxClient).to have_received(:create_post).once
    end

    it 'ADVBOX fora do ar: o lead já passou; o retry do job cria a tarefa uma vez, sem 2º encerramento (Review Focus 4)', :aggregate_failures do
      allow(Ramon::AdvboxClient).to receive(:create_post).and_raise(Ramon::AdvboxClient::UnavailableError)
      expect { described_class.call(lead) }.to raise_error(Ramon::AdvboxClient::UnavailableError)
      expect(lead.reload.lead_stage).to eq(juridico)

      allow(Ramon::AdvboxClient).to receive(:create_post).and_return({ 'posts_id' => 777 })
      described_class.call(lead.reload)

      expect(lead.reload.custom_attributes.dig('advbox', 'analise_posts_id')).to eq(777)
      expect(enviadas.count).to eq(1)
    end

    context 'when o Ganho não abriu o caso no ADVBOX (sem lawsuits_id)' do
      let(:advbox) { { 'erro' => 'AdvBox respondeu HTTP 422' } }

      it 'vai ao Jurídico sem tarefa e os administradores são avisados com o motivo (Review Focus 2)', :aggregate_failures do
        described_class.call(lead)

        expect(lead.reload.lead_stage).to eq(juridico)
        expect(Ramon::AdvboxClient).not_to have_received(:create_post)
        expect(avisos.pluck(:user_id)).to eq([admin.id])
        expect(avisos.first.meta['label']).to include('ANÁLISE DO CASO', 'ADVBOX')
        expect(Ramon::NtfyPushJob).to have_received(:perform_later) # sem dado pessoal: só a tese
          .with(lead.id, title: 'Jurídico: ANÁLISE DO CASO pendente (Tese Spec Passagem)', body: 'Veja o aviso no sino')
      end
    end

    # Review do PR 6, item 4: sem erro no lead, o ADVBOX do Ganho só não rodou ainda; o retomar cria a tarefa quando rodar.
    context 'when o caso do Ganho ainda não chegou do ADVBOX (sem lawsuits_id e sem erro)' do
      let(:advbox) { {} }

      it 'vai ao Jurídico sem tarefa e sem alarme' do
        described_class.call(lead)

        expect(lead.reload.lead_stage).to eq(juridico)
        expect(avisos).to be_empty
      end
    end
  end

  it 'lead em Fechado (legado) com o checklist completo: nada muda (Review Focus 1)', :aggregate_failures do
    completo_em(account.lead_stages.find_by!(label: Ramon::EtapaDeGanho::FECHADO))
    cliente_escreveu(1.hour)

    described_class.call(lead)

    expect(lead.reload.lead_stage.label).to eq(Ramon::EtapaDeGanho::FECHADO)
    expect(enviadas).to be_empty
    expect(Ramon::AdvboxClient).not_to have_received(:create_post)
  end

  it 'chave desligada: nada muda' do
    completo_em(documentos)
    with_modified_env(RAMON_ETAPA_DOCUMENTOS: nil) { described_class.call(lead) }
    expect(lead.reload.lead_stage).to eq(documentos)
  end

  describe 'gancho no lead' do
    before { lead.update_columns(conversation_id: conversa.id, won_at: 1.day.ago) } # rubocop:disable Rails/SkipsModelValidations

    def completar! = lead.reload.update!(custom_attributes: { 'doc_status' => { item.id.to_s => 'recebido' } })

    it 'checklist que completa em Documentos enfileira a passagem' do
      lead.update_columns(lead_stage_id: documentos.id) # rubocop:disable Rails/SkipsModelValidations
      expect { completar! }.to have_enqueued_job(Ramon::Documentos::PassagemJob).with(lead.id)
    end

    it 'no Jurídico (desmarcou e remarcou), não: nenhuma 2ª tarefa nem 2º encerramento (Review Focus 3)' do
      lead.update_columns(lead_stage_id: juridico.id) # rubocop:disable Rails/SkipsModelValidations
      expect { completar! }.not_to have_enqueued_job(Ramon::Documentos::PassagemJob)
    end

    it 'em Fechado, não' do
      lead.update_columns(lead_stage_id: account.lead_stages.find_by!(label: Ramon::EtapaDeGanho::FECHADO).id) # rubocop:disable Rails/SkipsModelValidations
      expect { completar! }.not_to have_enqueued_job(Ramon::Documentos::PassagemJob)
    end
  end

  # Spec §8 (ajuste de 07/11): o lead não volta para Documentos sozinho, mas a equipe sempre fica sabendo — a cada desmarcação
  # (review do PR 6, item 5), num job: quem desmarcou não pode tomar erro.
  describe 'desmarcar um documento de quem já está no Jurídico' do
    let(:pessoa) { create(:user, account: account, role: :agent, name: 'Ana Conferente') }

    before do
      Current.user = pessoa
      allow(Ramon::AdvboxClient).to receive(:settings).and_return({ 'users' => [] })
    end

    after { Current.user = nil }

    def marcar!(status, id = item.id)
      lead.reload.update!(custom_attributes: lead.custom_attributes.deep_merge('doc_status' => { id.to_s => status }))
    end

    def rotulos = avisos.order(:id).map { |aviso| [aviso.user_id, aviso.meta['label']] }

    it 'enfileira o aviso com o documento e quem desmarcou' do
      completo_em(juridico)
      expect { marcar!('pendente') }.to have_enqueued_job(Ramon::Documentos::DesmarcadoJob).with(lead.id, [item.id.to_s], pessoa.id)
    end

    it 'avisa o SDR e o responsável da ANÁLISE DO CASO, com nota e histórico; a tarefa e a etapa ficam', :aggregate_failures do
      sdr = create(:user, account: account, role: :agent)
      eduardo = create(:user, account: account, role: :agent)
      allow(Ramon::AdvboxClient).to receive(:settings).and_return({ 'users' => [{ 'id' => 266_778, 'email' => eduardo.email.upcase }] })
      completo_em(juridico)
      lead.update_columns(sdr_id: sdr.id) # rubocop:disable Rails/SkipsModelValidations

      perform_enqueued_jobs(only: Ramon::Documentos::DesmarcadoJob) { marcar!('pendente') }

      texto = 'CNIS completo foi desmarcado de Maria da Silva, que já está no Jurídico: decidir se volta para Documentos'
      expect(rotulos).to contain_exactly([sdr.id, texto], [eduardo.id, texto]) # não todos os administradores
      expect(conversa.messages.where(private: true).last.content).to include(texto, 'Ana Conferente')
      expect(historico.last).to include(texto, 'Ana Conferente')
      expect(Ramon::NtfyPushJob).to have_received(:perform_later)
        .with(lead.id, title: 'Jurídico: documento desmarcado (Tese Spec Passagem)', body: 'Decidir se volta para Documentos')
      expect(lead.reload.lead_stage).to eq(juridico)
      expect(Ramon::AdvboxClient).not_to have_received(:create_post)
    end

    it 'toda desmarcação avisa, mesmo com o checklist já incompleto; remarcar, não' do
      outro = create(:thesis_item, thesis: tese, section: 'documento', title: 'RG')
      completo_em(juridico)
      marcar!('recebido', outro.id)

      perform_enqueued_jobs(only: Ramon::Documentos::DesmarcadoJob) do
        marcar!('pendente')
        marcar!('pendente', outro.id)
        marcar!('recebido')
      end

      expect(avisos.pluck(:meta).pluck('label')).to contain_exactly(a_string_starting_with('CNIS completo foi'), a_string_starting_with('RG foi'))
    end

    it 'em Documentos, não avisa (o agente segue pedindo)' do
      completo_em(documentos)
      expect { marcar!('pendente') }.not_to have_enqueued_job(Ramon::Documentos::DesmarcadoJob)
    end
  end
end
