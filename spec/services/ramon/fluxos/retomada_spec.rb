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
end
