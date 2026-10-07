require 'rails_helper'

RSpec.describe Ramon::Fluxos::EventosAdvbox do
  # A conta seeda o funil no after_create (Novo ... Fechado is_won / Perdido is_lost).
  let(:account) { create(:account) }
  let(:lead) { novo_lead('+5548999000001') }

  def novo_lead(fone)
    contato = create(:contact, account: account, phone_number: fone)
    create(:lead, account: account, lead_stage: account.lead_stages.order(:position).first, contact: contato, name: 'Maria da Silva')
  end

  def migrado(modo: 'sombra')
    fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox', 'cancelar_se_sair_da_etapa' => false },
                                          ['registrar_atividade', { 'texto' => 'pelo fluxo: {texto}' }]),
                    origem: 'usuario', sistema_chave: 'eventos_advbox', modo: modo)
  end

  def atividades(kinds) = lead.lead_activities.where(kind: kinds).order(:id).pluck(:kind)

  describe 'a decisão é do evento (lida uma vez)' do
    it 'código no comando (padrão): o código faz; o fluxo migrado só ensaia, antes, na hora' do
      fluxo = migrado
      described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA')
      expect(atividades(%w[advbox_marco fluxo])).to eq(['advbox_marco'])
      expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[true, 'concluida']])
    end

    it 'fluxo no comando: só o fluxo age, na hora (dentro do job do ADVBOX); o código não faz nada' do
      fluxo = migrado(modo: 'normal')
      with_modified_env(RAMON_FLUXO_EVENTOS_ADVBOX: 'on') { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(atividades(%w[advbox_marco fluxo])).to eq(['fluxo'])
      expect(lead.lead_activities.find_by(kind: 'fluxo').to_value).to eq('pelo fluxo: SENTENCA PROFERIDA')
      expect(fluxo.execucoes.pluck(:ensaio, :status)).to eq([[false, 'concluida']])
    end

    it 'fluxo no comando mas ocupado com o mesmo lead (execução viva): o código faz este evento — nada se perde, nada em dobro' do
      fluxo = migrado(modo: 'normal')
      fluxo.execucoes.create!(account: account, alvo: lead, status: 'esperando', retomar_em: 5.minutes.from_now)
      with_modified_env(RAMON_FLUXO_EVENTOS_ADVBOX: 'on') { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(atividades(%w[advbox_marco fluxo])).to eq(['advbox_marco'])
      expect(fluxo.execucoes.count).to eq(1) # a viva; este evento não criou outra
    end

    it 'fluxo no comando mas o filtro de regras do gatilho não pega o evento: o código faz (o filtro não desliga efeito)' do
      fluxo = fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox', 'regras' => ['exito'] }, ['parar', {}]),
                              origem: 'usuario', sistema_chave: 'eventos_advbox', modo: 'normal')
      with_modified_env(RAMON_FLUXO_EVENTOS_ADVBOX: 'on') { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(atividades(%w[advbox_marco fluxo])).to eq(['advbox_marco'])
      expect(fluxo.execucoes.count).to eq(0)
    end

    it 'os fluxos comuns de evento do ADVBOX seguem como sempre: depois, sem a decisão, com as variáveis do código' do
      comum = fluxo_publicado(account, grafo_linear({ 'tipo' => 'evento_advbox' }, ['registrar_atividade', { 'texto' => 'comum' }]))
      travel_to(Time.zone.parse('2026-10-07 13:00:00 UTC')) { described_class.processar(lead, 'marco', 'SENTENCA PROFERIDA') }
      expect(comum.execucoes.sole.contexto['gatilho'])
        .to eq('regra' => 'marco', 'texto' => 'SENTENCA PROFERIDA', 'primeiro_nome' => 'Maria', 'hoje' => '07/10/2026')
    end
  end

  it 'primeiro nome como o código escreve nos rascunhos: lead sem nome vira "cliente"' do
    expect([described_class.primeiro_nome(lead), described_class.primeiro_nome(Lead.new(name: nil))]).to eq(%w[Maria cliente])
  end
end
