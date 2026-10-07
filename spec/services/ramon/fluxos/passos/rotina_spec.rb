require 'rails_helper'

RSpec.describe Ramon::Fluxos::Passos::Rotina do
  # A conta seeda o funil no after_create (Leads::SeedDefaultConfigService): 1 etapa is_won.
  let(:account) { create(:account) }
  let(:ganho) { account.lead_stages.find_by!(is_won: true) }
  let(:lead) { create(:lead, account: account, lead_stage: ganho, name: 'Maria da Silva') }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }

  # ensaio pode repetir no mesmo exemplo; execução de verdade, 1 por exemplo (índice único)
  def rodar(rotina, ensaio: false)
    ctx = Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: lead, ensaio: ensaio))
    described_class.rotina({ 'rotina' => rotina }, ctx)[:resumo]
  end

  def advbox_no_ar
    allow(Ramon::AdvboxClient).to receive_messages(create_customer: { 'customers_id' => 11 },
                                                    create_lawsuit: { 'lawsuits_id' => 22 }, create_post: { 'posts_id' => 33 })
  end

  describe 'dossiê de passagem' do
    it 'escreve o mesmo dossiê do código, não repete em 5 min, e o ensaio só descreve' do
      expect(rodar('dossie_passagem', ensaio: true)).to eq('faria: dossiê de passagem nas notas do lead')
      expect(lead.lead_notes.count).to eq(0)
      expect(rodar('dossie_passagem')).to eq('dossiê de passagem nas notas do lead')
      expect(lead.lead_notes.sole.body).to start_with('📋 DOSSIÊ')
      expect(rodar('dossie_passagem', ensaio: true)).to eq('dossiê: já há um dos últimos 5 min (não repete)')
    end
  end

  describe 'pesquisa NPS' do
    it 'o mesmo rascunho do código, uma vez por fase (ganho e êxito são travas separadas)' do
      expect(rodar('pesquisa_nps')).to eq('rascunho da pesquisa NPS (comercial) nas notas do lead')
      expect(lead.lead_notes.sole.body).to start_with('RASCUNHO (revisar antes de enviar) — pesquisa NPS:')
      expect(lead.reload.custom_attributes.dig('nps', 'pedido_em')).to be_present
      expect(rodar('pesquisa_nps', ensaio: true)).to start_with('pesquisa NPS (comercial): já pedida em ')
      expect(rodar('pesquisa_nps_exito', ensaio: true)).to eq('faria: rascunho da pesquisa NPS (exito) nas notas do lead')
    end
  end

  it 'execução atrasada, com o lead já fora do ganho: dossiê e NPS do ganho não escrevem nada (como os callbacks do Lead)' do
    lead.update!(lead_stage: account.lead_stages.order(:position).first)
    expect(rodar('dossie_passagem')).to eq('dossiê: o lead não está mais ganho, não escreveu')
    fluxo.execucoes.sole.update!(status: 'concluida') # libera o índice: 1 execução viva por fluxo e lead
    expect(rodar('pesquisa_nps')).to eq('pesquisa NPS (comercial): o lead não está mais ganho, não pediu')
    expect(lead.lead_notes.count).to eq(0)
    expect(lead.reload.custom_attributes['nps']).to be_nil
  end

  describe 'caso no ADVBOX (mesma garantia de hoje)' do
    it 'abre cliente, processo e tarefa pelo mesmo serviço do código; já aberto não chama de novo' do
      advbox_no_ar
      with_modified_env(ADVBOX_API_TOKEN: 'tok') do
        expect(rodar('abrir_caso_advbox', ensaio: true)).to start_with('faria: abrir o caso no ADVBOX')
        expect(rodar('abrir_caso_advbox')).to eq('caso aberto no ADVBOX (processo 22)')
        expect(rodar('abrir_caso_advbox', ensaio: true)).to start_with('ADVBOX: caso já aberto em ')
      end
      expect(Ramon::AdvboxClient).to have_received(:create_customer).once
      expect(lead.reload.custom_attributes['advbox']).to include('customers_id' => 11, 'lawsuits_id' => 22, 'posts_id' => 33)
    end

    it 'sem token não abre e segue (o código nem enfileirava); lead que saiu do ganho também não' do
      advbox_no_ar
      with_modified_env(ADVBOX_API_TOKEN: nil) do
        expect(rodar('abrir_caso_advbox', ensaio: true)).to eq('ADVBOX: sem token no hub, não abriu o caso (como o código)')
      end
      with_modified_env(ADVBOX_API_TOKEN: 'tok') do
        lead.update!(lead_stage: account.lead_stages.order(:position).first)
        expect(rodar('abrir_caso_advbox')).to eq('ADVBOX: o lead não está mais ganho, não abriu o caso')
      end
      expect(Ramon::AdvboxClient).not_to have_received(:create_customer)
    end

    it 'ADVBOX fora do ar: sobe o erro para o motor tentar de novo, com o id já criado guardado (não duplica)' do
      allow(Ramon::AdvboxClient).to receive(:create_customer).and_return('customers_id' => 11)
      allow(Ramon::AdvboxClient).to receive(:create_lawsuit).and_raise(Ramon::AdvboxClient::UnavailableError, 'AdvBox indisponível')
      with_modified_env(ADVBOX_API_TOKEN: 'tok') do
        expect { rodar('abrir_caso_advbox') }.to raise_error(Ramon::AdvboxClient::UnavailableError)
      end
      expect(lead.reload.custom_attributes.dig('advbox', 'customers_id')).to eq(11)
    end

    it 'ADVBOX recusou (4xx): fica anotado no lead, como hoje, e o fluxo segue' do
      allow(Ramon::AdvboxClient).to receive(:create_customer).and_raise(Ramon::AdvboxClient::RequestError.new(422, { 'erro' => 'x' }))
      resumo = with_modified_env(ADVBOX_API_TOKEN: 'tok') { rodar('abrir_caso_advbox') }
      expect(resumo).to start_with('ADVBOX recusou: ')
      expect(lead.reload.custom_attributes.dig('advbox', 'erro')).to be_present
    end
  end

  describe 'concluir tarefas (ADVBOX arquivado)' do
    it 'conclui só as abertas do lead; o ensaio conta' do
      lead.lead_tasks.create!(account: account, kind: 'follow_up', title: 'Aberta', due_at: 1.day.from_now)
      lead.lead_tasks.create!(account: account, kind: 'other', title: 'Feita', due_at: 1.day.ago, completed_at: 1.hour.ago)
      expect(rodar('concluir_tarefas', ensaio: true)).to eq('faria: concluir 1 tarefa(s) aberta(s) do lead')
      expect(rodar('concluir_tarefas')).to eq('concluiu 1 tarefa(s) aberta(s) do lead')
      expect(lead.lead_tasks.open_tasks.count).to eq(0)
    end
  end

  it 'rotina desconhecida falha na hora (não adianta repetir)' do
    expect { rodar('apagar_tudo') }.to raise_error(Ramon::Fluxos::PassoImpossivel, /rotina desconhecida/)
  end
end
