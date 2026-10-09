require 'rails_helper'

RSpec.describe Ramon::Fluxos::Rotinas::Externos do
  let(:account) { create(:account) }
  let(:fluxo) { fluxo_publicado(account, grafo_linear({ 'tipo' => 'manual' })) }
  let(:chegada) do
    account.chegadas.create!(criado_por: create(:user, account: account), destinatario: create(:user, account: account),
                             cliente_nome: 'Maria')
  end

  # ensaio pode repetir no mesmo exemplo; execução de verdade, 1 por alvo por exemplo (índice único)
  def rodar(rotina, alvo, ensaio: false)
    ctx = Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: alvo, ensaio: ensaio))
    described_class.public_send(rotina, ctx)
  end

  describe 'escalar a chegada' do
    it 'escala como o job (o alerta volta ao vivo para quem avisou); já escalada não mexe' do
      expect(rodar('escalar_chegada', chegada, ensaio: true)).to eq('faria: escalar — o alerta volta a tocar na tela de quem avisou')
      expect { rodar('escalar_chegada', chegada) }.to have_enqueued_job(ActionCableBroadcastJob)
      expect(chegada.reload.estado).to eq('escalado')
      expect(rodar('escalar_chegada', chegada, ensaio: true)).to eq('chegada já respondida (ou já escalada): não escala')
    end

    it 'respondida dentro dos 3 min: não escala' do
      chegada.update!(resposta: 'Já vou', respondido_em: Time.current)
      expect(rodar('escalar_chegada', chegada)).to eq('chegada já respondida (ou já escalada): não escala')
      expect(chegada.reload.escalado_em).to be_nil
    end
  end

  it 'com o alvo errado ("Testar com um lead…") falha na hora, dizendo com o que roda' do
    expect { rodar('escalar_chegada', create(:lead, account: account), ensaio: true) }
      .to raise_error(Ramon::Fluxos::PassoImpossivel, /uma chegada de cliente/)
  end

  it 'o passo Rotina pronta acha estas rotinas no registro (B5-conta) sem exigir lead' do
    ctx = Ramon::Fluxos::Contexto.new(fluxo.execucoes.create!(account: account, alvo: chegada, ensaio: true))
    expect(Ramon::Fluxos::Passos::Rotina.rotina({ 'rotina' => 'escalar_chegada' }, ctx))
      .to eq(saida: 's', resumo: 'faria: escalar — o alerta volta a tocar na tela de quem avisou')
    expect(Ramon::Fluxos::Rotinas.alvo('aviso_contrato')).to be_nil # regra fixa (08/10)
  end
end
