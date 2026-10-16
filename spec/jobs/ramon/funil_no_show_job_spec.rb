require 'rails_helper'

RSpec.describe Ramon::FunilNoShowJob do
  let(:account) { create(:account) }
  let(:closer) { create(:user, account: account) }
  let(:lead) { create(:lead, account: account, name: 'Maria Souza', closer_id: closer.id) }

  def reuniao(due_at, **attrs)
    create(:lead_task, account: account, lead: lead, kind: 'meeting', due_at: due_at, **attrs)
  end

  before { Ramon::FunilAutomatico.mudar!(account, 'no_show', 'on') }

  it 'reunião de 3h atrás sem registro: 1 nota-rascunho, 1 FunilAcao e sino pro Closer' do
    task = reuniao(3.hours.ago)
    expect { described_class.perform_now }.to change { lead.lead_notes.count }.by(1).and change(FunilAcao, :count).by(1)
    nota = lead.lead_notes.last.body
    expect(nota).to start_with('RASCUNHO (revisar antes de enviar) — remarcação:')
    expect(nota).to include('Oi Maria!', Ramon::ReuniaoAgendamento.quando(task.due_at))
    expect(FunilAcao.last).to have_attributes(acao: 'avisar_no_show', alvo: task.id.to_s, ensaio: false, desfazer: {})
    expect(Notification.where(user: closer, notification_type: 'ramon_meeting_reminder').count).to eq(1)
    expect(task.reload.completed_at).to be_nil
  end

  it 'rodar de novo não faz nada' do
    reuniao(3.hours.ago)
    described_class.perform_now
    expect { described_class.perform_now }.not_to(change { [lead.lead_notes.count, FunilAcao.count] })
  end

  it 'reunião concluída não gera nada' do
    reuniao(3.hours.ago, completed_at: 2.hours.ago)
    expect { described_class.perform_now }.not_to(change { [lead.lead_notes.count, FunilAcao.count] })
  end

  it 'reunião de 1h atrás e de 3 dias atrás não geram nada' do
    reuniao(1.hour.ago)
    reuniao(3.days.ago)
    expect { described_class.perform_now }.not_to(change { [lead.lead_notes.count, FunilAcao.count] })
  end

  it 'ensaio registra a ação uma vez só, sem nota nem sino' do
    Ramon::FunilAutomatico.mudar!(account, 'no_show', 'ensaio')
    reuniao(3.hours.ago)
    2.times { described_class.perform_now }
    expect(FunilAcao.where(ensaio: true).count).to eq(1)
    expect(lead.lead_notes.count).to eq(0)
  end

  it 'chave off não faz nada' do
    Ramon::FunilAutomatico.mudar!(account, 'no_show', 'off')
    reuniao(3.hours.ago)
    expect { described_class.perform_now }.not_to(change { [lead.lead_notes.count, FunilAcao.count] })
  end
end
