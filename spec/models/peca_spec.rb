require 'rails_helper'

RSpec.describe Peca do
  it 'monta a legenda inicial com as hashtags' do
    expect(create(:peca).legenda).to eq "Legenda base\n\n#inss #auxilioacidente"
  end

  it 'mantém legenda informada' do
    expect(create(:peca, legenda: 'minha').legenda).to eq 'minha'
  end

  it 'slug é único por conta' do
    peca = create(:peca)
    expect(build(:peca, account: peca.account, slug: peca.slug)).not_to be_valid
  end

  it 'transiciona quando a origem bate' do
    peca = create(:peca)
    peca.transicionar!(de: 'rascunho', para: 'aprovado')
    expect(peca.reload.status).to eq 'aprovado'
  end

  it 'recusa transição de origem errada' do
    peca = create(:peca, status: 'montando')
    expect { peca.transicionar!(de: 'rascunho', para: 'aprovado') }.to raise_error(Peca::TransicaoInvalida)
    expect(peca.reload.status).to eq 'montando'
  end

  it 'enfileira o espelho do Notion só quando o status muda' do
    peca = create(:peca)
    expect { peca.update!(legenda: 'x') }.not_to have_enqueued_job(Ramon::NotionEspelhoJob)
    expect { peca.update!(status: 'aprovado') }.to have_enqueued_job(Ramon::NotionEspelhoJob).with(peca.id)
  end

  it 'gatilho comum (N1 = B): mudar de status espelha no Notion como sempre e o fluxo comum de "Peça mudou de status" ouve' do
    peca = create(:peca)
    comum = fluxo_publicado(peca.account, grafo_linear({ 'tipo' => 'peca_mudou_status' }))
    expect { peca.update!(status: 'reprovado') }.to have_enqueued_job(Ramon::NotionEspelhoJob).with(peca.id)
    expect(comum.execucoes.sole.contexto.dig('gatilho', 'evento')).to eq('reprovado')
  end

  it 'travada? quando montando há mais de 15 min' do
    expect(build(:peca, status: 'montando', montagem_iniciada_em: 16.minutes.ago)).to be_travada
    expect(build(:peca, status: 'montando', montagem_iniciada_em: 5.minutes.ago)).not_to be_travada
  end
end
