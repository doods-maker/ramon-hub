require 'rails_helper'

RSpec.describe Ramon::AdvboxEventProcessor do
  # A conta seeda o funil no after_create (Novo ... Fechado is_won / Perdido is_lost).
  let(:account) { create(:account) }
  let(:stage_novo) { account.lead_stages.order(:position).first }
  let(:contact) { create(:contact, account: account, phone_number: '+5548999887766', cpf: '52998224725') }
  let!(:lead) { create(:lead, account: account, lead_stage: stage_novo, contact: contact, name: 'Maria da Silva') }

  def process(payload)
    event = AdvboxEvent.create!(account: account, event_key: SecureRandom.hex(16), payload: payload)
    described_class.new(event).perform
    event.reload
  end

  it 'CONTRATO FECHADO move o lead pra etapa ganha e registra atividade (match por CPF)' do
    event = process({ 'event' => 'stage.changed',
                      'process' => { 'stage' => 'CONTRATO FECHADO' },
                      'client' => { 'cpf' => '529.982.247-25' } })

    expect(event.status).to eq 'processed'
    expect(lead.reload.lead_stage.is_won).to be true
    expect(lead.won_at).to be_present
    expect(lead.lead_activities.where(kind: 'advbox_contrato_fechado')).to be_present
  end

  it 'REQUERIMENTO PROTOCOLADO cria follow-up de 45 dias (match por telefone com máscara)' do
    process({ 'process' => { 'stage' => 'REQUERIMENTO PROTOCOLADO' },
              'client' => { 'telefone' => '(48) 99988-7766' } })

    task = lead.lead_tasks.find_by(kind: 'follow_up')
    expect(task.title).to include 'INSS'
    expect(task.due_at).to be_within(1.minute).of(45.days.from_now)
    expect(lead.lead_activities.where(kind: 'advbox_inss_protocolado')).to be_present
  end

  it 'NEGADO cria tarefa urgente + rascunho de mensagem (nunca envia nada)' do
    process({ 'stage' => 'NEGADO / AVISAR CLIENTE', 'cpf' => '52998224725' })

    expect(lead.lead_tasks.find_by(kind: 'follow_up').due_at).to be_within(1.minute).of(1.day.from_now)
    note = lead.lead_notes.first
    expect(note.body).to start_with 'RASCUNHO'
    expect(note.body).to include 'Maria'
  end

  it 'normaliza acentos do payload (CARTA DE EXIGÊNCIAS → regra sem acento)' do
    event = process({ 'etapa' => 'CARTA DE EXIGÊNCIAS', 'cpf' => '52998224725' })

    expect(event.status).to eq 'processed'
    expect(lead.lead_activities.where(kind: 'advbox_exigencia')).to be_present
    expect(lead.lead_notes.first.body).to start_with 'RASCUNHO'
  end

  it 'BENEFÍCIO FUTURO cria reativação de longo prazo sem notificar' do
    process({ 'etapa' => 'BENEFÍCIO FUTURO / ANOTAR NA AGENDA', 'cpf' => '52998224725' })

    task = lead.lead_tasks.find_by(kind: 'follow_up')
    expect(task.due_at).to be_within(1.minute).of(180.days.from_now)
  end

  it 'êxito acha o lead mesmo já ganho (fallback do resolve) e deixa rascunho de comunicado' do
    lead.update!(lead_stage: account.lead_stages.find_by(is_won: true))

    event = process({ 'etapa' => 'RPV / PRECATÓRIO EMITIDO', 'cpf' => '52998224725' })

    expect(event.status).to eq 'processed'
    expect(lead.lead_activities.where(kind: 'advbox_exito')).to be_present
    # o handoff note do won_at também cria uma nota — buscar o rascunho pelo prefixo
    expect(lead.lead_notes.find_by("body LIKE 'RASCUNHO%'").body).to include 'êxito'
  end

  it 'contato só com caso de cálculo fica unmatched (fallback não adota caso oculto)' do
    outro = create(:contact, account: account, cpf: '11144477735')
    create(:lead, account: account, lead_stage: stage_novo, contact: outro, source: Lead::FONTE_CALCULO)

    event = process({ 'process' => { 'stage' => 'REQUERIMENTO PROTOCOLADO' },
                      'client' => { 'cpf' => '111.444.777-35' } })

    expect(event.status).to eq 'unmatched'
  end

  it 'ARQUIVADO encerra os follow-ups abertos do lead' do
    lead.lead_tasks.create!(account: account, kind: 'follow_up', title: 'Cobrar doc', due_at: 2.days.from_now)

    process({ 'etapa' => 'ARQUIVADO/ENCERRADO', 'cpf' => '52998224725' })

    expect(lead.lead_tasks.open_tasks).to be_empty
    expect(lead.lead_activities.where(kind: 'advbox_arquivado')).to be_present
  end

  it 'payload sem nome conhecido fica ignored com o cru preservado' do
    event = process({ 'etapa' => 'ETAPA QUE NAO EXISTE', 'cpf' => '52998224725' })

    expect(event.status).to eq 'ignored'
    expect(event.payload['etapa']).to eq 'ETAPA QUE NAO EXISTE'
    expect(lead.reload.lead_stage).to eq stage_novo
  end

  it 'regra conhecida sem CPF/telefone no payload fica unmatched' do
    event = process({ 'etapa' => 'CONTRATO FECHADO' })

    expect(event.status).to eq 'unmatched'
    expect(event.note).to include 'CONTRATO FECHADO'
    expect(lead.reload.lead_stage).to eq stage_novo
  end

  it 'BENEFÍCIO CONCEDIDO registra concessão e deixa rascunho de boa notícia' do
    event = process({ 'etapa' => 'BENEFÍCIO CONCEDIDO / IMPLANTAÇÃO', 'cpf' => '52998224725' })

    expect(event.status).to eq 'processed'
    expect(lead.lead_activities.where(kind: 'advbox_concessao')).to be_present
    expect(lead.lead_notes.first.body).to include 'CONCEDEU'
  end

  it 'PERICIA AGENDADA vira marco na Linha da Vida' do
    event = process({ 'etapa' => 'PERICIA AGENDADA', 'cpf' => '52998224725' })

    expect(event.status).to eq 'processed'
    expect(lead.lead_activities.where(kind: 'advbox_marco')).to be_present
  end

  it 'notifica via ntfy com título custom quando o tópico está configurado' do
    with_modified_env(NTFY_TOPIC: 'ramon-teste') do
      expect { process({ 'etapa' => 'SENTENÇA PROFERIDA', 'cpf' => '52998224725' }) }
        .to have_enqueued_job(Ramon::NtfyPushJob)
    end
  end
end
