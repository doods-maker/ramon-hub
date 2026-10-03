require 'rails_helper'

RSpec.describe Ramon::Papeis do
  let(:account) { create(:account) }
  let(:stage) { account.lead_stages.order(:position).first }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:bia) { create(:user, account: account, role: :agent) }
  let(:sdr_team) { create(:team, account: account, name: 'SDR') }

  def entra_no_time(team, *users)
    users.each { |user| create(:team_member, team: team, user: user) }
  end

  describe '.proximo' do
    it 'escolhe o membro com menos leads abertos naquele papel' do
      entra_no_time(sdr_team, ana, bia)
      create(:lead, account: account, lead_stage: stage, sdr: ana)

      expect(described_class.proximo(account, described_class::SDR)).to eq(bia)
    end

    it 'time vazio ou inexistente devolve nil' do
      expect(described_class.proximo(account, described_class::CLOSER)).to be_nil
    end
  end

  describe 'atribuição automática no Lead' do
    it 'lead novo nasce com o SDR do time' do
      entra_no_time(sdr_team, ana)

      expect(create(:lead, account: account, lead_stage: stage).sdr).to eq(ana)
    end

    it 'caso de cálculo e import ficam sem SDR', :aggregate_failures do
      entra_no_time(sdr_team, ana)

      expect(create(:lead, account: account, lead_stage: stage, source: Lead::FONTE_CALCULO).sdr_id).to be_nil
      Current.suppress_import_events = true
      expect(create(:lead, account: account, lead_stage: stage).sdr_id).to be_nil
    ensure
      Current.suppress_import_events = nil
    end

    it 'conversa sem responsável vira do SDR; com responsável, não mexe', :aggregate_failures do
      entra_no_time(sdr_team, ana)
      livre = create(:conversation, account: account)
      ocupada = create(:conversation, account: account, assignee: bia)

      create(:lead, account: account, lead_stage: stage, conversation: livre)
      create(:lead, account: account, lead_stage: stage, conversation: ocupada)

      expect(livre.reload.assignee).to eq(ana)
      expect(ocupada.reload.assignee).to eq(bia)
    end
  end

  describe '.atribuir_closer!' do
    let(:lead) { create(:lead, account: account, lead_stage: stage) }

    it 'preenche o Closer vazio com o membro do time closer' do
      entra_no_time(create(:team, account: account, name: 'closer'), bia)

      described_class.atribuir_closer!(lead)

      expect(lead.reload.closer).to eq(bia)
    end

    it 'não troca Closer já definido' do
      entra_no_time(create(:team, account: account, name: 'closer'), bia)
      lead.update!(closer: ana)

      described_class.atribuir_closer!(lead)

      expect(lead.reload.closer).to eq(ana)
    end
  end

  describe '.papel_de' do
    def no_time(nome)
      entra_no_time(create(:team, account: account, name: nome), ana)
    end

    it 'administrador é gestor' do
      admin = create(:user, account: account, role: :administrator)
      expect(described_class.papel_de(account, admin)).to eq('gestor')
    end

    it 'recepção (com acento) e controladoria viram recepcao' do
      no_time('Recepção')
      expect(described_class.papel_de(account, ana)).to eq('recepcao')
      expect(described_class.papel_de(account, bia)).to eq('equipe')
      entra_no_time(create(:team, account: account, name: 'controladoria'), bia)
      expect(described_class.papel_de(account, bia)).to eq('recepcao')
    end

    it 'closer vence sdr' do
      no_time('sdr')
      no_time('closer')
      expect(described_class.papel_de(account, ana)).to eq('closer')
    end

    it 'advogados vira advogada; sem time é equipe' do
      expect(described_class.papel_de(account, ana)).to eq('equipe')
      no_time('advogados')
      expect(described_class.papel_de(account, ana)).to eq('advogada')
    end
  end
end
