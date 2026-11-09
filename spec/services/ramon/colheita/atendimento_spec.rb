require 'rails_helper'

RSpec.describe Ramon::Colheita::Atendimento do
  let(:account) { create(:account) }
  let(:thesis) { account.theses.find_by!(name: 'Auxílio por incapacidade temporária (auxílio-doença / B31)') }
  let(:conversation) { create(:conversation, account: account) }
  let(:colheita) do
    {
      'dados' => {
        'cliente' => {
          'nome_completo' => 'Maria Teste Souza', 'profissao' => 'costureira',
          'representante' => { 'nome' => 'Carlos Teste', 'parentesco' => 'filho', 'motivo' => 'mãe sem celular' }
        },
        'incapacidade' => { 'parou_em' => '2024-05-15', 'afastado_hoje' => 'afastado', 'limitacoes_atuais' => 'não levanta o braço' },
        'saude' => { 'doencas' => [{ 'nome' => 'tendinite', 'cid' => 'M75' }, { 'nome' => 'bursite', 'cid' => nil }] },
        'segurado' => { 'regime_na_data' => nil, 'servidor_rpps' => '' },
        'beneficios' => [{ 'especie' => 'B31', 'situacao' => 'cessado', 'dcb' => '2024-08-30' }],
        'outras_teses_sinal' => [{ 'tese' => 'Auxílio-acidente', 'motivo' => 'sequela após alta' }]
      },
      'lacunas' => [{ 'campo' => 'saude.doencas[0].diagnostico_em', 'como_obter' => 'laudo médico' }],
      'confirmar' => ['incapacidade.limitacoes_atuais', 'saude.doencas[0].cid'],
      'fontes' => { 'incapacidade.parou_em' => '02/06', 'saude.doencas[0].nome' => '03/06' },
      'trechos' => [{ 'campo' => 'incapacidade.limitacoes_atuais', 'texto' => 'minha senha do gov é Tx9#kLm2 e não levanto o braço' }],
      'extraida_em' => '2026-11-09T15:30:00Z'
    }
  end
  let(:lead) do
    create(:lead, account: account, name: 'Maria', thesis: thesis, conversation: conversation,
                  custom_attributes: { 'colheita' => colheita })
  end
  let(:md) { described_class.markdown(lead) }

  before do
    create(:message, conversation: conversation, account: account, message_type: :incoming, content: 'oi',
                     created_at: Time.utc(2026, 6, 2, 15))
    create(:message, conversation: conversation, account: account, message_type: :outgoing, content: 'olá',
                     created_at: Time.utc(2026, 6, 10, 15))
    create(:message, conversation: conversation, account: account, message_type: :outgoing, content: 'nota', private: true,
                     created_at: Time.utc(2026, 7, 1, 15))
  end

  it 'usa o nome da colheita no título, avisa que é relato e traz tese e período público da conversa' do
    expect(md).to start_with('# Atendimento — Maria Teste Souza')
    expect(md).to include('extraído pela IA do hub em 09/11/2026 12:30', 'não prova')
    expect(md).to include('- **Tese:** Auxílio por incapacidade temporária', '- **Conversa:** 02/06/2026 a 10/06/2026')
  end

  it 'põe o representante só no cabeçalho' do
    expect(md).to include('- **Quem conversou:** Carlos Teste (filho) — mãe sem celular')
    expect(md.scan('Carlos Teste').size).to eq(1)
  end

  it 'não mostra quem conversou sem representante' do
    colheita['dados']['cliente'].delete('representante')
    expect(md).not_to include('Quem conversou')
  end

  it 'marca fonte (dd/mm) e (confirmar) e converte datas' do
    expect(md).to include('- Parou em: 15/05/2024 (02/06)')
    expect(md).to include('- Limitacoes atuais: não levanta o braço (confirmar)')
    expect(md).to include('- Afastado hoje: afastado')
  end

  it 'lista de objetos vira sub-bullets, com marcas do caminho aninhado' do
    expect(md).to include("- Doencas (03/06) (confirmar):\n  - nome: tendinite · cid: M75\n  - nome: bursite")
  end

  it 'ignora fonte inválida' do
    colheita['fontes']['saude.doencas'] = 'lixo'
    colheita['fontes'].delete('saude.doencas[0].nome')
    expect(md).to include('- Doencas (confirmar):')
  end

  it 'respeita a ordem dos blocos, pula bloco vazio e põe sinais em seção própria' do
    expect(md.index('## Cliente')).to be < md.index('## Beneficios')
    expect(md.index('## Beneficios')).to be < md.index('## Incapacidade')
    expect(md).not_to include('## Segurado')
    expect(md).not_to include('## Outras teses sinal')
    expect(md).to include("## Sinais de outra tese\n- Auxílio-acidente: sequela após alta")
    expect(md).to include('- especie: B31 · situacao: cessado · dcb: 30/08/2024')
  end

  it 'não repete o representante na seção Cliente' do
    expect(md).not_to include('Representante')
  end

  it 'mascara a senha no trecho' do
    expect(md).to include('## Trechos do relato', '[senha]')
    expect(md).not_to include('Tx9#kLm2')
  end

  it 'lista lacunas' do
    expect(md).to include('## O que falta', '- Saude · Doencas · Diagnostico em: laudo médico')
  end

  it 'renderiza colheita antiga sem fontes/trechos, sem datas' do
    colheita.delete('fontes')
    colheita.delete('trechos')
    expect(md).to include('- Parou em: 15/05/2024')
    expect(md).not_to include('(02/06)')
    expect(md).not_to include('## Trechos do relato')
  end

  it 'sem colheita traz cabeçalho e "Nada colhido da conversa ainda."' do
    lead.update!(custom_attributes: {})
    expect(md).to start_with('# Atendimento — Maria')
    expect(md).to include('Nada colhido da conversa ainda.')
    expect(md).not_to include('## ')
  end

  it 'sem conversa omite a linha Conversa' do
    lead.update!(conversation: nil)
    expect(md).not_to include('**Conversa:**')
  end
end
