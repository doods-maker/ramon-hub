require 'rails_helper'

# View scenic do roteiro da tese (F4, spec 2026-10-13 §3.9) — consultada por SQL, como o Metabase.
RSpec.describe 'view bi_roteiro' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:novo) { account.lead_stages.find_by!(name: 'Novo') }
  let(:thesis) { create(:thesis, account: account) }

  def linha(lead) = ActiveRecord::Base.connection.select_all("SELECT * FROM bi_roteiro WHERE lead_id = #{lead.id}").to_a.first

  def conversa(attrs) = create(:conversation, account: account, custom_attributes: attrs)

  # Review Focus 5.
  it 'mostra tese, passo, desfecho e datas do roteiro sem expor o texto das respostas' do
    roteiro = { 'tese_id' => thesis.id, 'passo' => nil, 'desfecho' => 'qualificado', 'decisivo' => 'sequela',
                'respostas' => { 'nome' => { 'valor' => 'Maria Souza', 'em' => '2026-10-14T10:00:00-03:00' },
                                 'sequela' => { 'valor' => 'dor no ombro', 'saida' => 'limitacao', 'em' => '2026-10-14T10:04:00-03:00' } } }
    limite = { 'limite' => 'qualificacao', 'modo' => 'piloto_ate_qualificacao', 'em' => '2026-10-14T10:05:00-03:00' }
    lead = create(:lead, account: account, thesis: thesis, lead_stage: novo, custom_attributes: { 'roteiro' => roteiro },
                         conversation: conversa('copiloto_modo' => 'rascunho', 'copiloto_limite' => limite))

    expect(linha(lead)).to include('thesis_name' => thesis.name, 'desfecho' => 'qualificado', 'passo_decisivo' => 'sequela',
                                   'respondidos' => 2, 'em_roteiro' => true, 'aguarda_equipe' => false,
                                   'modo' => 'rascunho', 'limite_atingido' => 'qualificacao')
    expect(linha(lead)['ultima_resposta_em']).to be_present
    expect(linha(lead).values.join(' ')).not_to include('Maria Souza', 'dor no ombro')
  end

  it 'lead sem roteiro só entra com o carimbo do limite; sem nenhum dos dois fica de fora' do
    sem_nada = create(:lead, account: account, thesis: thesis, lead_stage: novo)
    so_limite = create(:lead, account: account, thesis: thesis, lead_stage: novo,
                              conversation: conversa('copiloto_limite' => { 'limite' => 'reuniao', 'em' => '2026-10-14T11:00:00-03:00' }))

    expect(linha(sem_nada)).to be_nil
    expect(linha(so_limite)).to include('em_roteiro' => false, 'limite_atingido' => 'reuniao', 'respondidos' => 0, 'desfecho' => nil)
  end
end
