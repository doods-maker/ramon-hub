require 'rails_helper'

RSpec.describe Ramon::DossieService do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.order(:position).first }

  describe '#perform' do
    it 'compila pessoa e origem com atribuição' do
      contact = create(:contact, account: account, name: 'Maria', phone_number: '+5548999990000',
                                 data_nascimento: 30.years.ago.to_date,
                                 custom_attributes: { 'consent_marketing' => true },
                                 additional_attributes: { 'city' => 'Tubarão' })
      lead = create(:lead, account: account, lead_stage: stage, contact: contact,
                           source: 'anuncio-meta-auxilio', value: 25_000,
                           custom_attributes: { 'utm' => { 'utm_campaign' => 'aux-acidente' } })

      payload = described_class.new(lead: lead).perform

      expect(payload[:pessoa]).to include(lead_name: lead.name, idade: 30, cidade: 'Tubarão',
                                          consent_marketing: true, value: 25_000.0)
      expect(payload[:origem]).to include(channel: 'meta_ads', channel_label: 'Meta Ads', indicacao: false)
      expect(payload[:origem][:utm]).to eq('utm_campaign' => 'aux-acidente')
    end

    it 'marca indicação quando o canal derivado é indicacao' do
      lead = create(:lead, account: account, lead_stage: stage, source: 'indicacao-cliente')
      expect(described_class.new(lead: lead).perform[:origem][:indicacao]).to be true
    end

    it 'monta a tese com honorário formatado e objeções do playbook' do
      thesis = create(:thesis, account: account, honorario_percentual: 30, honorario_n_mensalidades: 3)
      create(:thesis_item, thesis: thesis, section: 'objecao', title: 'É caro', content: 'Só paga se ganhar.')
      lead = create(:lead, account: account, lead_stage: stage, thesis: thesis)

      tese = described_class.new(lead: lead).perform[:tese]

      expect(tese[:name]).to eq(thesis.name)
      expect(tese[:honorario_text]).to eq('30% dos atrasados + 3 mensalidades')
      expect(tese[:objecoes]).to eq([{ title: 'É caro', content: 'Só paga se ganhar.' }])
    end

    it 'formata percentual fracionado com vírgula e omite mensalidades zeradas' do
      thesis = create(:thesis, account: account, honorario_percentual: 12.5, honorario_n_mensalidades: 0)
      lead = create(:lead, account: account, lead_stage: stage, thesis: thesis)
      expect(described_class.new(lead: lead).perform[:tese][:honorario_text]).to eq('12,5% dos atrasados')
    end

    it 'expõe a última triagem e sinaliza awaiting_human quando done sem viabilidade' do
      lead = create(:lead, account: account, lead_stage: stage)
      lead.lead_triages.create!(account: account, status: 'done', viability: 'alta')
      last = lead.lead_triages.create!(account: account, status: 'done', result: 'sem conclusão')

      triagem = described_class.new(lead: lead).perform[:triagem]

      expect(triagem[:id]).to eq(last.id)
      expect(triagem[:awaiting_human]).to be true
      expect(triagem[:result]).to eq('sem conclusão')
    end

    it 'não marca awaiting_human quando a viabilidade foi detectada' do
      lead = create(:lead, account: account, lead_stage: stage)
      lead.lead_triages.create!(account: account, status: 'done', viability: 'alta')
      expect(described_class.new(lead: lead).perform[:triagem][:awaiting_human]).to be false
    end

    it 'mescla atividades e notas na timeline' do
      lead = create(:lead, account: account, lead_stage: stage)
      lead.lead_notes.create!(account: account, body: 'Cliente vai pensar')

      timeline = described_class.new(lead: lead).perform[:timeline]

      expect(timeline.map { |item| item[:type] }).to include('activity', 'note')
      note = timeline.find { |item| item[:type] == 'note' }
      expect(note[:body]).to eq('Cliente vai pensar')
    end

    it 'limita a timeline a 10 itens, mais recente primeiro' do
      lead = create(:lead, account: account, lead_stage: stage)
      12.times { |i| lead.lead_activities.create!(account: account, kind: 'stage_changed', to_value: "Etapa #{i}") }

      timeline = described_class.new(lead: lead).perform[:timeline]

      expect(timeline.size).to eq(10)
      expect(timeline.map { |item| item[:created_at] }).to eq(timeline.map { |item| item[:created_at] }.sort.reverse)
      expect(timeline.first[:to_value]).to eq('Etapa 11')
    end

    it 'lista tarefas abertas e documentos faltantes do checklist' do
      thesis = create(:thesis, account: account)
      received = create(:thesis_item, thesis: thesis, section: 'documento', title: 'CNIS')
      create(:thesis_item, thesis: thesis, section: 'documento', title: 'Laudo')
      lead = create(:lead, account: account, lead_stage: stage, thesis: thesis,
                           custom_attributes: { 'doc_status' => { received.id.to_s => 'recebido' } })
      create(:lead_task, account: account, lead: lead, title: 'Confirmar reunião')
      done = create(:lead_task, account: account, lead: lead, title: 'Já feita')
      done.update!(completed_at: Time.current)

      pendencias = described_class.new(lead: lead).perform[:pendencias]

      expect(pendencias[:tasks].map { |task| task[:title] }).to eq(['Confirmar reunião'])
      expect(pendencias[:docs_missing]).to eq([{ title: 'Laudo', status: 'pendente' }])
    end

    it 'não quebra em lead sem contato, tese ou triagem' do
      lead = create(:lead, account: account, lead_stage: stage)

      payload = described_class.new(lead: lead).perform

      expect(payload[:triagem]).to be_nil
      expect(payload[:tese]).to be_nil
      expect(payload[:pessoa][:idade]).to be_nil
      expect(payload[:pendencias]).to eq(tasks: [], docs_missing: [])
    end
  end

  describe 'esteira, docs, calculos e reunioes (Ficha)' do
    # A conta já vem semeada com o funil padrão (Leads::SeedDefaultConfigService,
    # 8 etapas incl. 'Novo'/'Negociação') — usamos essas etapas em vez de criar
    # nomes novos, pra não colidir com a uniqueness de lead_stages#name.
    let(:lead) { create(:lead, account: account, lead_stage: account.lead_stages.find_by!(name: 'Negociação')) }

    subject(:payload) { described_class.new(lead: lead).perform }

    it 'monta a esteira ordenada com a etapa atual marcada' do
      esteira = payload[:esteira]
      expect(esteira.map { |e| e[:name] }).to eq(account.lead_stages.order(:position).pluck(:name))
      current = esteira.find { |e| e[:current] }
      expect(current[:name]).to eq('Negociação')
      expect(current[:entered_at]).to eq(lead.stage_entered_at)
    end

    it 'expõe probability e origem do valor estimado em pessoa' do
      lead.update!(custom_attributes: (lead.custom_attributes || {}).merge('valor_estimado' => { 'origem' => 'auto' }))
      expect(payload[:pessoa][:probability]).to eq(75)
      expect(payload[:pessoa][:valor_estimado_origem]).to eq('auto')
    end

    it 'lista calculos e reunioes recentes do lead' do
      reuniao = Reuniao.create!(account: account, user: create(:user, account: account), lead: lead, titulo: 'Fechamento')
      expect(payload[:reunioes].first).to include(id: reuniao.id, titulo: 'Fechamento')
      expect(payload[:calculos]).to eq([])
    end

    it 'docs traz o checklist completo com status' do
      expect(payload[:docs]).to include(:received, :total, :itens)
    end
  end
end
