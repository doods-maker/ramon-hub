require 'rails_helper'

RSpec.describe CopilotSuggestion do
  let(:account) { create(:account) }
  let(:lead) { create(:lead, account: account, name: 'Maria das Dores') }

  def sugestao(acao, extras = {})
    account.copilot_suggestions.create!(lead: lead, kind: 'acao', status: 'pending',
                                        payload: { 'acao' => acao, 'texto' => 'faz isso' }.merge(extras))
  end

  describe '#apply! com acao zapsign' do
    it 'gera o contrato e guarda o link como nota' do
      allow(Ramon::ZapsignContractService).to receive(:new).with(lead).and_return(
        instance_double(Ramon::ZapsignContractService,
                        perform: { 'sign_url' => 'https://app.zapsign.com.br/abc', 'faltando' => ['{{profissão}}'] })
      )
      suggestion = sugestao('zapsign')

      expect(suggestion.apply!).to be(true)
      expect(suggestion.reload.status).to eq('applied')
      expect(lead.lead_notes.last.body).to include('https://app.zapsign.com.br/abc').and include('{{profissão}}')
    end

    it 'continua pendente quando o zapsign falha' do
      allow(Ramon::ZapsignContractService).to receive(:new).with(lead).and_raise(
        Ramon::ZapsignClient::UnavailableError, 'timeout'
      )
      suggestion = sugestao('zapsign')

      expect(suggestion.apply!).to be(false)
      expect(suggestion.reload.status).to eq('pending')
      expect(suggestion.motivo_da_recusa).to include('ZapSign')
    end
  end

  describe '#apply! com acao advbox' do
    it 'recusa enquanto o caso nao esta ganho' do
      suggestion = sugestao('advbox')

      expect(suggestion.apply!).to be(false)
      expect(suggestion.motivo_da_recusa).to include('ganho')
    end

    it 'enfileira a abertura do caso quando ja esta ganho' do
      lead.update!(lead_stage: create(:lead_stage, account: account, name: 'Ganho', is_won: true))
      suggestion = sugestao('advbox')

      expect(Ramon::AdvboxClosingJob).to receive(:perform_later).with(lead.id)

      expect(suggestion.apply!).to be(true)
      expect(suggestion.reload.status).to eq('applied')
    end
  end

  describe '#apply! com acao reuniao' do
    it 'cria a tarefa de reuniao na esteira' do
      suggestion = sugestao('reuniao', 'quando' => 1.week.from_now.iso8601, 'titulo' => 'Fechamento')

      expect(suggestion.apply!).to be(true)
      expect(lead.lead_tasks.last).to have_attributes(kind: 'meeting', title: 'Fechamento')
    end

    it 'recusa quando a data nao veio na sugestao' do
      suggestion = sugestao('reuniao')

      expect(suggestion.apply!).to be(false)
      expect(suggestion.motivo_da_recusa).to include('data')
    end
  end

  describe '#apply! com acao perdido' do
    let!(:aberta) { create(:lead_stage, account: account, name: 'Contato', is_lost: false, position: 1) }
    let!(:perdida) { create(:lead_stage, account: account, name: 'Perdido', is_lost: true, position: 9) }

    it 'move o caso para a etapa perdida com o motivo' do
      lead.update!(lead_stage: aberta)
      suggestion = sugestao('perdido', 'lost_reason' => 'Sem direito')

      expect(suggestion.apply!).to be(true)
      expect(lead.reload).to have_attributes(lead_stage_id: perdida.id, lost_reason: 'Sem direito')
      expect(lead.lost_at).to be_present
    end

    it 'recusa quando o caso ja esta ganho' do
      lead.update!(lead_stage: create(:lead_stage, account: account, name: 'Ganho', is_won: true, position: 8))
      suggestion = sugestao('perdido', 'lost_reason' => 'Sem direito')

      expect(suggestion.apply!).to be(false)
      expect(suggestion.motivo_da_recusa).to include('ganho')
    end

    it 'recusa sem etapa perdida configurada' do
      perdida.destroy!
      expect(sugestao('perdido', 'lost_reason' => 'x').apply!).to be(false)
    end
  end

  describe '#apply! nos tipos antigos' do
    it 'draft continua virando nota rascunho' do
      suggestion = account.copilot_suggestions.create!(lead: lead, kind: 'draft', status: 'pending',
                                                       payload: { 'texto' => 'Oi Maria, tudo bem?' })

      expect(suggestion.apply!).to be(true)
      expect(lead.lead_notes.last.body).to include('RASCUNHO').and include('Oi Maria')
    end

    it 'move_stage recusa etapa que nao existe' do
      suggestion = account.copilot_suggestions.create!(lead: lead, kind: 'move_stage', status: 'pending',
                                                       payload: { 'etapa_sugerida' => 'Etapa fantasma' })

      expect(suggestion.apply!).to be(false)
      expect(suggestion.motivo_da_recusa).to include('Etapa sugerida')
    end
  end
end
