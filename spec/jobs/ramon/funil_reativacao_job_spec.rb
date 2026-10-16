require 'rails_helper'

RSpec.describe Ramon::FunilReativacaoJob do
  let(:account) { create(:account) }
  let(:sdr) { create(:user, account: account) }
  let(:perdido) { account.lead_stages.find_by(is_lost: true) }
  let(:hoje) { Time.find_zone('America/Sao_Paulo').local(2026, 10, 16, 10, 0) }
  let(:lead) { create(:lead, account: account, name: 'Maria Souza', sdr_id: sdr.id) }

  def perder(dias, motivo: 'Sumiu / não respondeu', alvo: lead)
    alvo.update!(lead_stage: perdido, lost_reason: motivo)
    alvo.update_column(:lost_at, hoje - dias.days) # rubocop:disable Rails/SkipsModelValidations
  end

  before do
    Ramon::FunilAutomatico.mudar!(account, 'reativacao', 'on')
    travel_to(hoje)
  end

  it 'perdido por sumiço há 30 dias: nota-rascunho, tarefa pro SDR e FunilAcao com o id da tarefa' do
    perder(30)
    expect { described_class.perform_now }.to change { lead.lead_notes.count }.by(1).and change { lead.lead_tasks.count }.by(1)
    expect(lead.lead_notes.last.body).to start_with('RASCUNHO (revisar antes de enviar) — retomada:').and include('Oi Maria, tudo bem?')
    task = lead.lead_tasks.last
    expect(task).to have_attributes(kind: 'follow_up', title: 'Retomar contato (30 dias)', user_id: sdr.id)
    expect(task.due_at).to eq(hoje)
    expect(FunilAcao.last).to have_attributes(acao: 'reativar', alvo: '30', ensaio: false, desfazer: { 'task_id' => task.id })
  end

  it 'aos 60 dias usa o título de 60' do
    perder(60)
    described_class.perform_now
    expect(lead.lead_tasks.last.title).to eq('Retomar contato (60 dias)')
  end

  it 'perdido por outro motivo não gera nada' do
    perder(30, motivo: 'Honorário')
    expect { described_class.perform_now }.not_to(change { [lead.lead_notes.count, lead.lead_tasks.count, FunilAcao.count] })
  end

  it 'rodar duas vezes não repete' do
    perder(30)
    described_class.perform_now
    expect { described_class.perform_now }.not_to(change { [lead.lead_notes.count, lead.lead_tasks.count, FunilAcao.count] })
  end

  it 'perdido há 32 dias e ainda não processado (feriado/fim de semana) é coberto' do
    perder(32)
    expect { described_class.perform_now }.to change { lead.lead_tasks.count }.by(1)
  end

  it 'fora da janela (34 dias, entre as marcas) não gera nada' do
    perder(34)
    expect { described_class.perform_now }.not_to(change { [lead.lead_notes.count, lead.lead_tasks.count, FunilAcao.count] })
  end

  it 'ensaio só registra a FunilAcao, uma vez' do
    Ramon::FunilAutomatico.mudar!(account, 'reativacao', 'ensaio')
    perder(30)
    2.times { described_class.perform_now }
    expect(FunilAcao.where(ensaio: true).count).to eq(1)
    expect(lead.lead_notes.count + lead.lead_tasks.count).to eq(0)
  end

  it 'chave off não faz nada' do
    Ramon::FunilAutomatico.mudar!(account, 'reativacao', 'off')
    perder(30)
    expect { described_class.perform_now }.not_to(change { [lead.lead_notes.count, lead.lead_tasks.count, FunilAcao.count] })
  end
end
