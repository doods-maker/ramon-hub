# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RamonLeadListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, auto_create_lead: true) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:event) { Events::Base.new('conversation.created', Time.zone.now, conversation: conversation) }

  it 'cria um lead na etapa Novo linkado ao contato/conversa' do
    expect { listener.conversation_created(event) }.to change { account.leads.count }.by(1)
    lead = account.leads.last
    expect(lead.contact_id).to eq(contact.id)
    expect(lead.conversation_id).to eq(conversation.id)
    expect(lead.lead_stage).to eq(account.lead_stages.find_by(name: 'Novo'))
  end

  it 'não cria se a inbox não tem auto_create_lead' do
    inbox.update!(auto_create_lead: false)
    expect { listener.conversation_created(event) }.not_to(change { account.leads.count })
  end

  it 're-aponta a conversa do lead existente (dedup por contato)' do
    first = create(:conversation, account: account, inbox: inbox, contact: contact)
    listener.conversation_created(Events::Base.new('conversation.created', Time.zone.now, conversation: first))
    expect { listener.conversation_created(event) }.not_to(change { account.leads.count })
    expect(account.leads.last.conversation_id).to eq(conversation.id)
  end

  it 'cria lead NOVO quando os leads do contato estão todos fechados (pessoa ≠ caso)' do
    won_stage = account.lead_stages.find_by(is_won: true)
    old_conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    old_lead = create(:lead, account: account, contact: contact, conversation: old_conversation,
                             lead_stage: won_stage)

    expect { listener.conversation_created(event) }.to change { account.leads.count }.by(1)
    new_lead = account.leads.reorder(:id).last
    expect(new_lead.id).not_to eq(old_lead.id)
    expect(new_lead.lead_stage).to eq(account.lead_stages.order(:position).first)
    expect(old_lead.reload.conversation_id).to eq(old_conversation.id)
  end

  describe '#message_created -> atribuição do referral da Meta' do
    let(:lead) do
      create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                    conversation: conversation, contact: contact)
    end
    let(:referral) do
      { 'source_id' => '12034', 'source_type' => 'ad', 'source_url' => 'https://fb.me/xyz',
        'headline' => 'Machucou no trabalho?', 'ctwa_clid' => 'clid-abc' }
    end
    let(:message) do
      create(:message, account: account, conversation: conversation, message_type: :incoming,
                       content: 'oi', content_attributes: { referral: referral })
    end

    it 'grava source e meta_referral (com ctwa_clid) no lead' do
      lead
      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
      lead.reload
      expect(lead.source).to eq('anuncio-meta: 12034')
      expect(lead.custom_attributes['meta_referral']).to include('ctwa_clid' => 'clid-abc', 'source_id' => '12034')
    end

    it 'não sobrescreve source já preenchido, mas guarda o referral' do
      lead.update!(source: 'bpc-loas')
      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
      lead.reload
      expect(lead.source).to eq('bpc-loas')
      expect(lead.custom_attributes['meta_referral']).to include('ctwa_clid' => 'clid-abc')
    end

    it 'ignora mensagem sem referral' do
      lead
      plain = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')
      expect { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: plain)) }
        .not_to(change { lead.reload.custom_attributes })
    end

    context 'when deriving channel on first contact' do
      it 'turns an unsigned whatsapp lead into indicacao' do
        lead.update!(channel: 'outro', source: nil)
        incoming = create(:message, account: account, conversation: conversation, message_type: :incoming,
                                    content: 'oi, tudo bem?')
        listener.message_created(Events::Base.new('message.created', Time.zone.now, message: incoming))
        expect(lead.reload.channel).to eq('indicacao')
      end

      it 'derives channel and source from a signature message' do
        lead.update!(channel: 'outro', source: nil)
        incoming = create(:message, account: account, conversation: conversation, message_type: :incoming,
                                    content: 'Olá! Vim pelo site do escritório e gostaria de falar com a equipe.')
        listener.message_created(Events::Base.new('message.created', Time.zone.now, message: incoming))
        expect(lead.reload).to have_attributes(channel: 'google_seo', source: 'site-institucional')
      end

      it 'does not override a channel that is already derived' do
        lead.update!(channel: 'landing_page', source: 'auxilio-acidente')
        incoming = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')
        listener.message_created(Events::Base.new('message.created', Time.zone.now, message: incoming))
        expect(lead.reload.channel).to eq('landing_page')
      end

      it 'derives instagram from an instagram inbox without signature' do
        instagram_inbox = create(:channel_instagram, account: account).inbox
        instagram_conversation = create(:conversation, account: account, inbox: instagram_inbox, contact: contact)
        lead.update!(channel: 'outro', source: nil, conversation: instagram_conversation)
        incoming = create(:message, account: account, conversation: instagram_conversation, message_type: :incoming,
                                    content: 'vi o perfil de vocês')
        listener.message_created(Events::Base.new('message.created', Time.zone.now, message: incoming))
        expect(lead.reload.channel).to eq('instagram')
      end
    end
  end

  describe '#message_created -> IA casa anexo com item do checklist' do
    let(:lead) do
      create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                    conversation: conversation, contact: contact)
    end

    context 'when the incoming message has an image attachment' do
      it 'enqueues Ramon::DocMatchJob' do
        lead
        message = create(:message, account: account, conversation: conversation, message_type: :incoming)
        message.attachments.create!(account_id: account.id, file_type: :image,
                                    file: fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png'))
        expect { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message)) }
          .to have_enqueued_job(Ramon::DocMatchJob).with(message.id)
      end
    end

    context 'when the incoming message has no attachment' do
      it 'does not enqueue Ramon::DocMatchJob' do
        lead
        message = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')
        expect { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message)) }
          .not_to have_enqueued_job(Ramon::DocMatchJob)
      end
    end
  end

  describe '#message_created -> coach de objeção' do
    let(:thesis) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
    let(:lead) do
      create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                    conversation: conversation, contact: contact, thesis: thesis)
    end

    it 'enfileira Ramon::CoachObjecaoJob para incoming com texto e lead com tese' do
      lead
      message = create(:message, account: account, conversation: conversation, message_type: :incoming,
                                 content: 'vou pensar mais um pouco, tá caro pra mim')
      expect { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message)) }
        .to have_enqueued_job(Ramon::CoachObjecaoJob).with(message.id)
    end

    it 'não enfileira para incoming curta (< 20 chars)' do
      lead
      message = create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'oi')
      expect { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message)) }
        .not_to have_enqueued_job(Ramon::CoachObjecaoJob)
    end
  end

  # Colheita NÃO é mais automática por mensagem (decisão 20/07: só sob demanda
  # pelo botão do painel / LeadColheitasController) — sem gatilho no message_created.
  describe '#message_created -> NÃO agenda colheita automática' do
    let(:thesis) { account.theses.find_by!(name: 'Auxílio-acidente (B36)') }
    let(:message) do
      create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'me machuquei')
    end

    it 'não enfileira o job de colheita nem para lead de auxílio-acidente' do
      create(:lead, account: account, thesis: thesis, conversation: conversation, contact: contact)
      expect { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message)) }
        .not_to have_enqueued_job(Ramon::ColheitaExtractionJob)
    end
  end

  describe '#lead_updated -> etiqueta a conversa' do
    it 'aplica a fase-* da etapa do lead na conversa' do
      lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                           conversation: conversation, contact: contact)
      lead.update!(lead_stage: account.lead_stages.find_by(label: 'fase-qualificacao'))
      ev = Events::Base.new('lead.updated', Time.zone.now, lead: lead)
      listener.lead_updated(ev)
      expect(conversation.reload.label_list).to contain_exactly('fase-qualificacao')
    end
  end

  describe '#conversation_updated -> move o lead' do
    it 'move o lead pra etapa da fase-* adicionada' do
      lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                           conversation: conversation, contact: contact)
      ev = Events::Base.new('conversation.updated', Time.zone.now,
                            conversation: conversation,
                            changed_attributes: { 'label_list' => [[], ['fase-qualificacao']] })
      listener.conversation_updated(ev)
      expect(lead.reload.lead_stage).to eq(account.lead_stages.find_by(label: 'fase-qualificacao'))
    end

    it 'ignora quando label_list não mudou' do
      lead = create(:lead, account: account, lead_stage: account.lead_stages.find_by(label: 'fase-novo'),
                           conversation: conversation, contact: contact)
      ev = Events::Base.new('conversation.updated', Time.zone.now,
                            conversation: conversation,
                            changed_attributes: { 'status' => %w[open resolved] })
      expect { listener.conversation_updated(ev) }.not_to(change { lead.reload.lead_stage_id })
    end
  end

  describe 'SLA da 1ª resposta pelo fluxo (B4.2)' do
    let(:sdr) { create(:user, account: account, role: :agent, name: 'Sara SDR') }
    let!(:gestor) { create(:user, account: account, role: :administrator, name: 'Gil Gestor') }
    let(:fluxo) { Ramon::Fluxos::Migracao.semear(account, 'sla').first }
    let(:dez) { Time.zone.parse('2026-10-05 13:00:00 UTC') } # segunda, 10h em São Paulo

    # O relógio dos fluxos (Ramon::FluxoRelogioJob) sem o resto: anda o que venceu.
    def relogio
      FluxoExecucao.where(status: 'esperando', retomar_em: ..Time.current).find_each { |e| Ramon::Fluxos::Executor.new(e).avancar! }
    end

    def avisos = Notification.where(notification_type: 'ramon_fluxo_aviso').order(:id).map { |n| [n.user_id, n.meta['label']] }

    def trilha = FluxoExecucao.where(fluxo: fluxo).order(:id).flat_map(&:trilha).pluck('resumo')

    def nascer(momento = dez)
      travel_to(momento) do
        listener.conversation_created(event)
        relogio
      end
    end

    it 'sem a chave: o código vigia como sempre e o fluxo só ensaia (nunca os dois)' do
      fluxo
      travel_to(dez) do
        expect { listener.conversation_created(event) }.to have_enqueued_job(Ramon::FirstResponseSlaJob).with(conversation.id)
        relogio
      end
      travel_to(dez + 5.minutes + 30.seconds) { relogio }
      expect(FluxoExecucao.where(fluxo: fluxo).pluck(:ensaio)).to eq([true])
      expect(trilha).to include('faria: sino para Gil Gestor: "Lead aguardando 1ª resposta há 5 min: Maria"')
      expect(avisos).to be_empty
    end

    it 'o ouvinte geral (Conversa criada) não inicia o fluxo do SLA; o disparo do SLA não inicia os fluxos comuns' do
      fluxo
      comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'conversa_criada' }, ['parar', {}]))
      travel_to(dez) do
        RamonFluxoListener.instance.conversation_created(event)
        listener.conversation_created(event)
      end
      expect(FluxoExecucao.where(fluxo: comum).count).to eq(1)
      expect(FluxoExecucao.where(fluxo: fluxo).count).to eq(1)
    end

    describe 'com a chave (RAMON_FLUXO_SLA=on + o fluxo em modo normal)' do
      around { |ex| with_modified_env(RAMON_FLUXO_SLA: 'on') { ex.run } }

      before do
        fluxo
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'sla', 'normal')
      end

      it 'o fluxo vigia e o código não: SDR no prazo da caixa (com push), gestores aos 60 min (sem push)' do
        allow(Ramon::NtfyPushJob).to receive(:perform_later)
        travel_to(dez) do
          expect { listener.conversation_created(event) }.not_to have_enqueued_job(Ramon::FirstResponseSlaJob)
          account.leads.find_by!(conversation_id: conversation.id).update!(sdr_id: sdr.id)
          relogio
        end
        travel_to(dez + 5.minutes + 30.seconds) { relogio }
        travel_to(dez + 60.minutes + 30.seconds) { relogio }
        expect(avisos).to eq([[sdr.id, 'Lead aguardando 1ª resposta há 5 min: Maria'],
                              [gestor.id, 'Lead aguardando 1ª resposta há 60 min: Maria']])
        expect(Ramon::NtfyPushJob).to have_received(:perform_later)
          .with(title: 'Lead aguardando 1a resposta', body: 'Lead aguardando 1ª resposta há 5min: Maria').once
        expect(FluxoExecucao.where(fluxo: fluxo).pluck(:ensaio, :status)).to eq([[false, 'concluida']])
      end

      it 'respondeu antes do prazo: nada (nem aviso, nem escalada)' do
        nascer
        travel_to(dez + 2.minutes) { conversation.update!(first_reply_created_at: Time.current) }
        travel_to(dez + 5.minutes + 30.seconds) { relogio }
        expect(avisos).to be_empty
        expect(FluxoExecucao.where(fluxo: fluxo).pluck(:status)).to eq(['concluida'])
      end

      it 'aviso só no horário do passo (7h–21h, todo dia); a escalada é esperada mesmo fora dele' do
        cedo = Time.zone.parse('2026-10-05 09:30:00 UTC') # 6h30 em São Paulo
        nascer(cedo)
        travel_to(cedo + 5.minutes + 30.seconds) { relogio }  # 6h35: fora → sem aviso, segue para a escalada
        travel_to(cedo + 60.minutes + 30.seconds) { relogio } # 7h30: dentro → gestores
        expect(avisos).to eq([[gestor.id, 'Lead aguardando 1ª resposta há 60 min: Maria']])
      end

      it 'caixa com SLA de 60 min: aviso aos 60 e sem escalada (como o código)' do
        inbox.update!(first_response_sla_minutes: 60)
        nascer
        travel_to(dez + 60.minutes + 30.seconds) { relogio }
        expect(trilha.grep(/\Asino:/)).to eq(['sino: Lead aguardando 1ª resposta há 60 min: Maria'])
        expect(trilha).to include(a_string_ending_with('já passou: segue sem esperar'))
        expect(FluxoExecucao.where(fluxo: fluxo).pluck(:status)).to eq(['concluida'])
      end

      it 'voltar para sombra: conversa nova volta ao código na hora; a que o fluxo já vigiava termina pelo fluxo' do
        nascer
        Ramon::Fluxos::Migracao.mudar_modo!(account, 'sla', 'sombra')
        travel_to(dez + 1.minute) do
          outra = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account, name: 'Joana'))
          nova = Events::Base.new('conversation.created', Time.zone.now, conversation: outra)
          expect { listener.conversation_created(nova) }.to have_enqueued_job(Ramon::FirstResponseSlaJob).with(outra.id)
        end
        travel_to(dez + 5.minutes + 30.seconds) { relogio }
        expect(FluxoExecucao.where(fluxo: fluxo).order(:id).pluck(:ensaio)).to eq([false, true])
        expect(avisos).to eq([[gestor.id, 'Lead aguardando 1ª resposta há 5 min: Maria']])
      end

      it 'fluxo no comando que não pega a conversa (filtro de caixa editado) devolve aquela conversa ao código' do
        desenho = fluxo.reload.rascunho.deep_dup
        desenho['nos'].first['config']['caixa_ids'] = [inbox.id + 1]
        fluxo.update!(rascunho: desenho)
        fluxo.publicar!(nil)
        travel_to(dez) { expect { listener.conversation_created(event) }.to have_enqueued_job(Ramon::FirstResponseSlaJob) }
        expect(FluxoExecucao.where(fluxo: fluxo)).to be_empty
      end
    end
  end

  describe 'leads e conversas — código ou fluxo (B5-leads)' do
    # Chaves ligadas: sem os fluxos em modo normal, o código segue no comando (a chave é env + fluxo).
    around do |ex|
      chaves = { RAMON_FLUXO_CRIAR_LEAD: 'on', RAMON_FLUXO_ORIGEM_LEAD: 'on', RAMON_FLUXO_SUGESTAO_DOC: 'on', RAMON_FLUXO_COACH: 'on' }
      with_modified_env(chaves) { ex.run }
    end

    let(:anuncio) { { 'source_id' => '12034', 'headline' => 'Machucou no trabalho?' } }

    # Os ouvintes do hub na ordem REAL do AsyncDispatcher (os nativos não mexem em lead nem em fluxo).
    def publicar(nome, dados)
      ev = Events::Base.new(nome, Time.zone.now, dados)
      AsyncDispatcher.new.listeners.select { |l| l.class.name.start_with?('Ramon') }
                     .each { |l| l.public_send(ev.method_name, ev) if l.respond_to?(ev.method_name) }
    end

    # Cada disparo de fluxo, na ordem: [gatilho, grupo que decidiu (nil = os fluxos comuns), o que `olhar` vê naquela hora].
    # A decisão de cada grupo é gravada na entrada do Migracao.decidir; os fluxos comuns, no Disparo.call sem 'assumido'.
    def gravar_disparos(&olhar)
      ver = olhar
      disparos = []
      allow(Ramon::Fluxos::Migracao).to receive(:decidir).and_wrap_original do |original, nome, gatilho, alvo, dados = {}, &bloco|
        disparos << [gatilho, nome, ver.call]
        original.call(nome, gatilho, alvo, dados, &bloco)
      end
      allow(Ramon::Fluxos::Disparo).to receive(:call).and_wrap_original do |original, gatilho, alvo, dados = {}, **opcoes|
        disparos << [gatilho, nil, ver.call] unless dados.key?('assumido')
        original.call(gatilho, alvo, dados, **opcoes)
      end
      disparos
    end

    def lead_da_conversa = account.leads.find_by(conversation_id: conversation.id)

    def mensagem(conteudo, *traits, **attrs)
      create(:message, *traits, account: account, conversation: conversation, message_type: :incoming, content: conteudo, **attrs)
    end

    # Cria os fluxos do grupo e põe no comando (a env já está ligada no around).
    def assumir(grupo)
      Ramon::Fluxos::Migracao.semear(account, grupo)
      Ramon::Fluxos::Migracao.mudar_modo!(account, grupo, 'normal').first
    end

    it 'código no comando: o lead nasce antes do SLA e dos fluxos comuns de Conversa nova; lead.created sai 1 vez' do
      disparos = gravar_disparos { lead_da_conversa.present? }
      expect { publicar('conversation.created', conversation: conversation) }
        .to have_enqueued_job(Ramon::FirstResponseSlaJob).with(conversation.id)
        .and have_enqueued_job(EventDispatcherJob).with('lead.created', anything, anything).exactly(:once)
      expect(disparos).to eq([['conversa_criada', 'criar_lead', false], ['conversa_criada', 'sla', true], ['conversa_criada', nil, true]])
    end

    it 'código no comando: a origem é gravada antes dos fluxos comuns de Mensagem recebida' do
      create(:lead, account: account, contact: contact, conversation: conversation, channel: 'outro', source: nil)
      disparos = gravar_disparos { lead_da_conversa.source }
      publicar('message.created', message: mensagem('oi', content_attributes: { referral: anuncio }))
      expect(disparos).to eq([['mensagem_recebida', 'origem_lead', nil], ['mensagem_recebida', nil, 'anuncio-meta: 12034']])
    end

    it 'sem nada a anotar (canal já derivado, sem anúncio), a origem nem é decidida — só os fluxos comuns' do
      create(:lead, account: account, contact: contact, conversation: conversation, channel: 'landing_page', source: 'auxilio-acidente')
      disparos = gravar_disparos { nil }
      publicar('message.created', message: mensagem('oi'))
      expect(disparos).to eq([['mensagem_recebida', nil, nil]])
    end

    it 'fluxo no comando: a mesma ordem — o fluxo cria o lead na hora, antes do SLA e dos fluxos comuns; lead.created 1 vez' do
      fluxo = assumir('criar_lead')
      disparos = gravar_disparos { lead_da_conversa.present? }
      expect { publicar('conversation.created', conversation: conversation) }
        .to have_enqueued_job(Ramon::FirstResponseSlaJob).with(conversation.id)
        .and have_enqueued_job(EventDispatcherJob).with('lead.created', anything, anything).exactly(:once)
      expect(disparos).to eq([['conversa_criada', 'criar_lead', false], ['conversa_criada', 'sla', true], ['conversa_criada', nil, true]])
      expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
      expect(lead_da_conversa).to have_attributes(contact_id: contact.id, name: 'Maria', lead_stage: account.lead_stages.order(:position).first)
    end

    it 'em sombra (criado, ainda não virado): o código cria o lead e o fluxo só ensaia — 1 lead' do
      Ramon::Fluxos::Migracao.semear(account, 'criar_lead')
      publicar('conversation.created', conversation: conversation)
      trilha = Ramon::Fluxos::Migracao.fluxo(account, 'criar_lead_da_conversa').execucoes.sole.trilha.pluck('resumo')
      expect(trilha).to include('faria: criar o lead na 1ª etapa do funil (ou ligar a conversa ao lead aberto do contato)')
      expect(account.leads.where(contact_id: contact.id).count).to eq(1)
    end

    it 'fluxo no comando mas ocupado com a conversa: o código cria o lead (reserva) — nem 0 nem 2' do
      fluxo = assumir('criar_lead')
      fluxo.execucoes.create!(account: account, alvo: conversation, status: 'esperando', retomar_em: 5.minutes.from_now)
      publicar('conversation.created', conversation: conversation)
      expect(account.leads.where(conversation_id: conversation.id).count).to eq(1)
      expect(fluxo.execucoes.count).to eq(1)
    end

    it 'fluxo no comando: liga a conversa ao lead aberto do mesmo contato, sem lead novo (como o código)' do
      antiga = create(:conversation, account: account, inbox: inbox, contact: contact)
      aberto = create(:lead, account: account, name: 'Maria', contact: contact, conversation: antiga,
                             lead_stage: account.lead_stages.order(:position).first)
      fluxo = assumir('criar_lead')
      expect { publicar('conversation.created', conversation: conversation) }.not_to(change { account.leads.count })
      expect(aberto.reload.conversation_id).to eq(conversation.id)
      expect(fluxo.execucoes.sole.trilha.last['resumo']).to eq('conversa ligada ao lead aberto: Maria (Novo)')
    end

    it 'origem pelo fluxo: na hora, antes dos fluxos comuns de Mensagem recebida — a mesma origem do código' do
      create(:lead, account: account, contact: contact, conversation: conversation, channel: 'outro', source: nil)
      fluxo = assumir('origem_lead')
      disparos = gravar_disparos { lead_da_conversa.source }
      publicar('message.created', message: mensagem('oi', content_attributes: { referral: anuncio }))
      expect(disparos).to eq([['mensagem_recebida', 'origem_lead', nil], ['mensagem_recebida', nil, 'anuncio-meta: 12034']])
      expect(lead_da_conversa).to have_attributes(channel: 'meta_ads', source: 'anuncio-meta: 12034')
      expect(lead_da_conversa.custom_attributes['meta_referral']).to include('source_id' => '12034')
      expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
    end

    describe 'coach e sugestão de documento pelo fluxo (pela fila, como o código)' do
      let(:thesis) { create(:thesis, account: account) }
      let!(:lead) { create(:lead, account: account, contact: contact, conversation: conversation, thesis: thesis, channel: 'landing_page') }

      def llm(conteudo) = Ramon::LlmClient::Result.new(content: conteudo, input_tokens: 1, output_tokens: 1)

      def ev(msg) = Events::Base.new('message.created', Time.zone.now, message: msg)

      before { allow(Ramon::EventoInline).to receive(:registrar).and_call_original }

      it 'coach: o ouvinte não enfileira o job; o fluxo roda o mesmo coach (balão do coach) sem balão ⚙ na conversa' do
        create(:thesis_item, thesis: thesis, section: 'objecao', title: 'Advogado é caro', content: 'A análise é gratuita.')
        allow(Ramon::LlmClient).to receive(:complete)
          .and_return(llm('{"objecao": "custo", "opcoes": [{"titulo": "A", "texto": "a"}, {"titulo": "B", "texto": "b"}]}'))
        fluxo = assumir('coach')
        msg = mensagem('achei caro, vou pensar mais um pouco antes de fechar')
        expect { listener.message_created(ev(msg)) }.not_to have_enqueued_job(Ramon::CoachObjecaoJob)
        perform_enqueued_jobs(only: Ramon::FluxoAvancarJob)
        expect(Ramon::EventoInline).to have_received(:registrar).with(conversation, anything, hash_including(tipo: 'coach')).once
        expect(Ramon::EventoInline).not_to have_received(:registrar).with(anything, anything, hash_including(tipo: 'fluxo'))
        expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
      end

      it 'documento: o fluxo roda a mesma IA, grava a sugestão e o gatilho Documento recebido continua nascendo' do
        rg = create(:thesis_item, thesis: thesis, section: 'documento', content: 'RG')
        allow(Ramon::LlmClient).to receive(:complete).and_return(llm(%({"item_id": #{rg.id}})))
        comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'documento_recebido' }, ['parar', {}]))
        fluxo = assumir('sugestao_doc')
        msg = mensagem('segue', :with_attachment)
        expect { listener.message_created(ev(msg)) }.not_to have_enqueued_job(Ramon::DocMatchJob)
        perform_enqueued_jobs(only: Ramon::FluxoAvancarJob)
        expect(lead.reload.custom_attributes.dig('doc_sugestao', 'item_id')).to eq(rg.id)
        expect(comum.execucoes.count).to eq(1)
        expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
      end

      it 'rajada de anexos com o fluxo no comando: o 1º vai pelo fluxo, os outros pelo código — nenhum se perde, nenhum em dobro' do
        fluxo = assumir('sugestao_doc')
        pelo_codigo = []
        allow(Ramon::DocMatchJob).to receive(:perform_later) { |id| pelo_codigo << id }
        msgs = Array.new(3) { mensagem('foto', :with_attachment) }
        msgs.each { |m| listener.message_created(ev(m)) }
        expect(fluxo.execucoes.sole.contexto.dig('gatilho', 'mensagem_id')).to eq(msgs[0].id)
        expect(pelo_codigo).to eq([msgs[1].id, msgs[2].id])
      end
    end
  end
end
