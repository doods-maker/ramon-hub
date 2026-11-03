require 'rails_helper'

RSpec.describe 'Conferência de fases API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/ramon_conferencia_fases" }
  let(:sugestao) { { 'etapa' => 'EXECUÇÃO COMO EXEQUENTE', 'etapa_id' => 3_949_581 } }

  let(:arquivado) { { 'etapa_id' => 3_736_298, 'etapa' => 'ARQUIVADO/ENCERRADO', 'step' => 'ARQUIVAMENTO' } }

  before do
    Rails.cache.delete(Ramon::ConferenciaFases::ETAPAS_CACHE)
    allow(Ramon::AdvboxClient).to receive(:settings).and_return(
      { 'stages' => [{ 'id' => 3_736_298, 'stage' => 'ARQUIVADO/ENCERRADO', 'step' => 'ARQUIVAMENTO' }] }
    )
  end

  def conferencia(**attrs)
    account.ramon_conferencias_fase.create!({ lawsuit_id: rand(1..999_999), grupo: 'igual', cliente: 'FULANO' }.merge(attrs))
  end

  it 'exige autenticação' do
    get base
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lista filtrada por grupo e busca, com o resumo da carteira inteira' do
    conferencia(grupo: 'atrasada', cliente: 'SIEMES ELISEU LINS', numero: '5000939-49.2025.4.04.7216', sugestao: sugestao)
    conferencia(grupo: 'baixa', cliente: 'CAROLINE COMELI')
    get base, headers: agent.create_new_auth_token, params: { grupo: 'atrasada', q: '5000939' }
    expect(response.parsed_body['payload'].pluck('cliente')).to eq ['SIEMES ELISEU LINS']
    expect(response.parsed_body['resumo']['grupos']).to eq('atrasada' => 1, 'baixa' => 1)
    expect(response.parsed_body['permissoes']).to eq('aplicar' => false)
    expect(response.parsed_body['etapas']).to eq [arquivado]
  end

  it 'ADVBOX fora do ar não derruba a lista: só vem sem etapas' do
    allow(Ramon::AdvboxClient).to receive(:settings).and_raise(Ramon::AdvboxClient::UnavailableError)
    conferencia
    get base, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['etapas']).to eq []
  end

  it 'a equipe escolhe qualquer etapa do ADVBOX, mesmo sem sugestão; o nome vem do ADVBOX' do
    linha = conferencia(grupo: 'diferente')
    patch "#{base}/#{linha.id}", headers: agent.create_new_auth_token,
                                 params: { painel_marca: 'errado', obs: 'já pago', etapa_id: 3_736_298, etapa: 'FORJADA' }
    expect(linha.reload).to have_attributes(painel_marca: 'errado', obs: 'já pago', atualizar: true, etapa_escolhida: arquivado, marcado_por: agent)
    expect(response.parsed_body['etapa_id']).to eq 3_736_298
    expect(account.ramon_conferencias_fase.para_aplicar).to contain_exactly(linha)
  end

  it 'etapa que não existe no ADVBOX é recusada e não muda a linha' do
    linha = conferencia(grupo: 'atrasada', sugestao: sugestao)
    patch "#{base}/#{linha.id}", headers: agent.create_new_auth_token, params: { etapa_id: 1 }
    expect(response).to have_http_status(:not_found)
    expect(linha.reload).to have_attributes(atualizar: false, etapa_escolhida: nil)
  end

  it '"Não alterar" desfaz a escolha; escolher de novo reabre linha já aplicada' do
    linha = conferencia(atualizar: true, etapa_escolhida: arquivado, aplicado_em: Time.current, erro_aplicacao: 'x')
    patch "#{base}/#{linha.id}", headers: agent.create_new_auth_token, params: { etapa_id: nil }, as: :json
    expect(linha.reload).to have_attributes(atualizar: false, etapa_escolhida: nil, aplicado_em: nil, erro_aplicacao: nil)
    expect(response.parsed_body['etapa_id']).to be_nil
    linha.update!(aplicado_em: Time.current)
    patch "#{base}/#{linha.id}", headers: agent.create_new_auth_token, params: { etapa_id: 3_736_298 }, as: :json
    expect(linha.reload).to have_attributes(atualizar: true, aplicado_em: nil)
  end

  it 'marcar outro campo não mexe na etapa escolhida' do
    linha = conferencia(atualizar: true, etapa_escolhida: arquivado)
    patch "#{base}/#{linha.id}", headers: agent.create_new_auth_token, params: { obs: 'conferir' }
    expect(linha.reload).to have_attributes(obs: 'conferir', atualizar: true, etapa_escolhida: arquivado)
  end

  it 'aplicar no ADVBOX: só administrador' do
    conferencia(grupo: 'atrasada', sugestao: sugestao, atualizar: true)
    post "#{base}/aplicar", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect { post "#{base}/aplicar", headers: admin.create_new_auth_token }.to have_enqueued_job(Ramon::ConferenciaAplicarJob)
    expect(response.parsed_body).to eq('enfileirados' => 1)
  end
end
