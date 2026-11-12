require 'rails_helper'

describe Ramon::ContactAnonymizer do
  let(:account) { create(:account) }
  let(:contact) do
    create(:contact, account: account, name: 'Joao da Silva', email: 'contato@exemplo.com',
                     phone_number: '+5548999998888', cpf: '52998224725',
                     custom_attributes: { 'apelido' => 'Joaozinho' })
  end
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:message) do
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                     sender: contact, content: 'Sou o Joao, CPF 529.982.247-25, escreve pra contato@exemplo.com')
  end
  let!(:note) { create(:note, contact: contact, account: account, content: 'Cliente confirmou o CPF 529.982.247-25') }

  def perform
    described_class.new(contact).perform
  end

  it 'anonymizes the contact identity fields' do
    perform
    expect(contact.reload.name).to eq("Titular anonimizado ##{contact.id}")
    expect(contact.email).to be_nil
    expect(contact.phone_number).to be_nil
    expect(contact.cpf).to be_nil
    expect(contact.custom_attributes).to eq({})
  end

  it 'redacts PII from messages while preserving the conversation' do
    perform
    expect(message.reload.content).to include('[nome]')
    expect(message.content).to include('[cpf]')
    expect(message.content).not_to include('529.982.247-25')
    expect(message.content).not_to include('contato@exemplo.com')
    expect(conversation.reload).to be_present
  end

  it 'redacts PII from contact notes' do
    perform
    expect(note.reload.content).to include('[cpf]')
    expect(note.content).not_to include('529.982.247-25')
  end

  # Registro de ações: a trilha fica (somente-inclusão), só os valores de PII somem.
  it 'keeps the audit trail but redacts the old PII values', :aggregate_failures do
    contact.update!(phone_number: '+5548988887777', blocked: true)

    perform
    trilha = Audited.audit_class.where(auditable: contact).order(:id)
    edicao = trilha.find { |audit| audit.audited_changes.key?('blocked') && audit.action == 'update' }
    expect(edicao.audited_changes['phone_number']).to eq(%w[[anonimizado] [anonimizado]])
    expect(edicao.audited_changes['blocked']).to eq([false, true])
    expect(trilha.last.comment).to eq('anonimizado')
    expect(trilha.flat_map { |audit| audit.audited_changes.to_json }.join).not_to include('Joao', '52998224725', '8888')
  end

  it 'redacts the trail of a contact merged into this one' do
    duplicado = create(:contact, account: account, name: 'Joao Duplicado', phone_number: '+5548977776666')
    ContactMergeAction.new(account: account, base_contact: contact, mergee_contact: duplicado).perform

    perform
    destroy = Audited.audit_class.find_by(auditable_type: 'Contact', auditable_id: duplicado.id, action: 'destroy')
    expect(destroy.audited_changes.to_json).not_to include('Duplicado', '7777')
  end

  # Decisão de 11/11/2026: pedido de eliminação de cliente não apaga nada; fica registrado e a gestão decide.
  describe 'titular que é cliente' do
    let(:gestor) { create(:user, account: account, role: :administrator) }
    let(:won_stage) { account.lead_stages.find_by(is_won: true) }
    let(:open_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }

    before { gestor }

    def intacto
      expect(contact.reload).to have_attributes(name: 'Joao da Silva', email: 'contato@exemplo.com', cpf: '52998224725')
      expect(message.reload.content).to include('529.982.247-25')
      expect(note.reload.content).to include('529.982.247-25')
    end

    it 'cliente pelo contato: não apaga nada, registra no histórico do lead e avisa os gestores', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: won_stage, contact: contact, name: 'Lead ganho')

      expect { perform }.to raise_error(described_class::ClienteGanho)

      intacto
      expect(lead.lead_activities.where(kind: 'eliminacao_pedida').count).to eq(1)
      aviso = gestor.notifications.find_by(notification_type: 'ramon_fluxo_aviso')
      expect(aviso).to have_attributes(primary_actor: lead)
      expect(aviso.meta['label']).to include('Lead ganho')
    end

    it 'cliente só pela conversa (lead ganho sem contato ligado): não apaga nada', :aggregate_failures do
      create(:lead, account: account, lead_stage: won_stage, conversation: conversation)

      expect { perform }.to raise_error(described_class::ClienteGanho)
      intacto
    end

    it 'caso de cálculo sem contato, ligado pela conversa: não apaga nada', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: open_stage, conversation: conversation, source: Lead::FONTE_CALCULO)

      expect(lead).to have_attributes(contact_id: nil, won_at: nil)
      expect { perform }.to raise_error(described_class::ClienteGanho)
      intacto
    end

    # Sair da etapa de ganho zera won_at; o contrato que já existiu continua sendo caso de cliente.
    it 'contrato cancelado depois de apto (won_at zerado): não apaga nada', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: open_stage, contact: contact, apto_em: 1.month.ago, contrato_cancelado_em: 1.day.ago)

      expect(lead.won_at).to be_nil
      expect { perform }.to raise_error(described_class::ClienteGanho)
      intacto
    end

    it 'lead ganho e caso de cálculo mais novo: o pedido fica no histórico do lead do funil', :aggregate_failures do
      ganho = create(:lead, account: account, lead_stage: won_stage, contact: contact)
      create(:lead, account: account, lead_stage: open_stage, conversation: conversation, source: Lead::FONTE_CALCULO)

      expect { perform }.to raise_error(described_class::ClienteGanho)
      expect(ganho.lead_activities.where(kind: 'eliminacao_pedida').count).to eq(1)
    end

    it 'lead aberto (não ganho) não protege: o titular é anonimizado como antes', :aggregate_failures do
      lead = create(:lead, account: account, lead_stage: open_stage, contact: contact, conversation: conversation)

      perform

      expect(contact.reload.name).to eq("Titular anonimizado ##{contact.id}")
      expect(message.reload.content).not_to include('529.982.247-25')
      expect(lead.lead_activities.where(kind: 'eliminacao_pedida')).to be_empty
    end
  end

  # Decisões de 12/11/2026: quem não é cliente perde também o que ficou nos leads e nas conversas.
  describe 'titular que não é cliente: rastros fora do contato' do
    let(:open_stage) { account.lead_stages.find_by(is_won: false, is_lost: false) }
    let(:lead) do
      create(:lead, account: account, lead_stage: open_stage, contact: contact, conversation: conversation, name: 'Maria Souza',
                    portal_token: 'token-vivo', cnis: { 'filename' => 'cnis.pdf' }, lost_reason: 'Maria mudou de ideia',
                    benefit_monthly_value: 2100,
                    custom_attributes: { 'meta_referral' => { 'ctwa_clid' => 'abc' }, 'zapsign' => { 'cpf' => '52998224725' } })
    end

    it 'anonimiza o lead, guarda só a origem de marketing e mascara o nome do lead nas mensagens', :aggregate_failures do
      message.update_columns(content: 'Fala com a Maria', processed_message_content: 'CPF 529.982.247-25') # rubocop:disable Rails/SkipsModelValidations
      lead

      perform
      expect(lead.reload).to have_attributes(name: "Titular anonimizado ##{contact.id}", cnis: nil, portal_token: nil,
                                             benefit_monthly_value: nil, custom_attributes: { 'meta_referral' => { 'ctwa_clid' => 'abc' } })
      expect(lead.lost_reason).not_to include('Maria')
      expect(message.reload.content).not_to include('Maria')
      expect(message.processed_message_content).not_to include('529.982.247-25')
      expect(Audited.audit_class.where(auditable: lead).map { |a| a.audited_changes.to_json }.join).not_to include('Maria')
    end

    it 'mascara notas, tarefas, reuniões e histórico; apaga cálculos, sugestões e o texto da triagem', :aggregate_failures do
      nota = lead.lead_notes.create!(account: account, body: 'Joao passou o CPF 529.982.247-25')
      tarefa = create(:lead_task, account: account, lead: lead, title: 'Ligar para o Joao', meet_url: 'https://meet.google.com/x')
      reuniao = create(:reuniao, account: account, lead: lead, status: 'pronta', transcricao: 'Eu sou o Joao', ata: 'Joao da Silva quer revisar')
      atividade = lead.lead_activities.create!(account: account, kind: 'note_added', to_value: 'Joao mandou o RG')
      Calculo.create!(account: account, lead: lead, tipo: 'rmi', segurado_nome: 'Joao da Silva', snapshot: { 'cnis' => {} })
      create(:copilot_suggestion, account: account, lead: lead)
      triagem = lead.lead_triages.create!(account: account, status: 'done', source_text: 'Joao, 52998224725', result: 'viável')

      perform
      expect(nota.reload.body).to include('[nome]', '[cpf]')
      expect(tarefa.reload).to have_attributes(title: 'Ligar para o [nome]', meet_url: nil)
      expect([reuniao.reload.transcricao, reuniao.ata].join).not_to include('Joao')
      expect(atividade.reload.to_value).not_to include('Joao')
      expect([lead.calculos.count, lead.copilot_suggestions.count]).to eq([0, 0])
      expect(triagem.reload).to have_attributes(source_text: nil, result: nil, status: 'done')
    end

    it 'apaga todos os anexos (inclusive os da equipe), troca o source_id e limpa os atributos da conversa', :aggregate_failures do
      da_equipe = create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :outgoing)
      [message, da_equipe].each { |m| m.attachments.create!(account_id: account.id, file_type: :image, external_url: 'https://exemplo.com/rg.png') }
      conversation.update_columns(additional_attributes: { 'referer' => 'https://lp.exemplo.com/?nome=Joao' }) # rubocop:disable Rails/SkipsModelValidations
      contato_na_caixa = conversation.contact_inbox

      perform
      expect(Attachment.where(message_id: [message.id, da_equipe.id])).to be_empty
      expect(conversation.reload.additional_attributes).to eq({})
      expect(contato_na_caixa.reload.source_id).to eq("anonimizado-#{contato_na_caixa.id}")
    end

    it 'cancela o fluxo que ainda ia rodar e apaga o contexto das execuções', :aggregate_failures do
      fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'assinatura_painel' }))
      esperando = fluxo.execucoes.create!(account: account, alvo: lead, status: 'esperando', contexto: { 'nome' => 'Joao' }, trilha: ['g'])
      feita = fluxo.execucoes.create!(account: account, alvo: conversation, status: 'concluida', contexto: { 'msg' => 'Joao' })

      perform
      expect(esperando.reload).to have_attributes(status: 'cancelada', contexto: {}, trilha: [])
      expect(feita.reload).to have_attributes(status: 'concluida', contexto: {})
    end

    it 'não toca no lead de outro contato, nem no que aponta para a conversa do titular' do
      outro_contato = create(:contact, account: account, name: 'Pedro Alves')
      outro = create(:lead, account: account, lead_stage: open_stage, contact: outro_contato, conversation: conversation,
                            name: 'Pedro Alves', portal_token: 'dele')

      perform
      expect(outro.reload).to have_attributes(name: 'Pedro Alves', portal_token: 'dele')
    end

    it 'contato com petição é cliente: nada é apagado', :aggregate_failures do
      advogada = create(:user, account: account)
      account.peticoes.create!(contact: contact, criado_por: advogada, responsavel: advogada, inicial: true, tribunal: 'tjsc')

      expect { perform }.to raise_error(described_class::ClienteGanho)
      expect(message.reload.content).to include('529.982.247-25')
    end

    it 'falha no meio desfaz tudo (transação)', :aggregate_failures do
      lead
      allow(contact).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

      expect { perform }.to raise_error(ActiveRecord::RecordInvalid)
      expect(message.reload.content).to include('529.982.247-25')
      expect(lead.reload).to have_attributes(name: 'Maria Souza', portal_token: 'token-vivo')
    end

    describe 'pasta do Drive do lead' do
      before { lead.update_columns(custom_attributes: lead.custom_attributes.merge('drive' => { 'pasta_id' => 'pasta-1' })) } # rubocop:disable Rails/SkipsModelValidations

      it 'vai para a lixeira depois da eliminação e fica no histórico do lead', :aggregate_failures do
        allow(Ramon::DriveClient).to receive(:lixeira)

        perform
        expect(Ramon::DriveClient).to have_received(:lixeira).with('pasta-1').once
        expect(lead.lead_activities.where(kind: 'drive_lixeira').count).to eq(1)
      end

      it 'Drive falhou: a eliminação vale e o histórico guarda a pasta para apagar à mão', :aggregate_failures do
        allow(Ramon::DriveClient).to receive(:lixeira).and_raise(Google::Apis::ClientError, 'insufficientFilePermissions')

        perform
        expect(contact.reload.name).to eq("Titular anonimizado ##{contact.id}")
        expect(lead.lead_activities.find_by(kind: 'drive_lixeira_falhou').to_value).to eq('pasta-1')
      end
    end
  end

  it 'records the bulk deletion as made by who asked', :aggregate_failures do
    admin = create(:user, account: account, role: :administrator)
    Contacts::BulkActionService.new(account: account, user: admin, params: { action_name: 'delete', ids: [contact.id] }).perform

    audit = Audited.audit_class.where(auditable: contact).order(:id).last
    expect(audit.comment).to eq('anonimizado_em_massa')
    expect(audit.user).to eq(admin)
  end
end
