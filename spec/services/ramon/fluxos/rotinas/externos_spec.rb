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

  it 'os pesados pedem o MESMO job de hoje (fila e novas tentativas do código); o ensaio só descreve' do
    assinatura = create(:portal_assinatura, portal_cliente: create(:portal_cliente, account: account))
    envio = create(:portal_envio, portal_cliente: assinatura.portal_cliente)
    reuniao = create(:reuniao, account: account)
    peca = create(:peca, account: account)
    expect(rodar('escrever_ata', reuniao, ensaio: true)).to start_with('faria: transcrever o áudio e escrever a ata')
    expect { rodar('conferir_assinatura_painel', assinatura) }.to have_enqueued_job(Ramon::ZapsignStatusJob).with(assinatura.id)
    expect { rodar('processar_envio_painel', envio) }.to have_enqueued_job(Ramon::PortalEnvioJob).with(envio.id)
    expect { rodar('escrever_ata', reuniao) }.to have_enqueued_job(Ramon::ReuniaoAtaJob).with(reuniao.id)
    expect { rodar('acervo_drive', peca) }.to have_enqueued_job(Ramon::ConteudoDriveJob).with(peca.id)
    expect { rodar('espelho_notion', peca, ensaio: true) }.not_to have_enqueued_job(Ramon::NotionEspelhoJob)
  end

  describe 'aviso do contrato' do
    it 'o mesmo histórico e o mesmo sino de hoje, pelo status que o código gravou no selo' do
      user = create(:user, account: account)
      lead = create(:lead, account: account, custom_attributes: {
                      'zapsign' => { 'doc_token' => 'd1', 'status' => 'signed', 'template_name' => 'Contrato' }
                    })
      expect(rodar('aviso_contrato', lead, ensaio: true)).to eq('faria: histórico e sino a todos — contrato assinado')
      expect(rodar('aviso_contrato', lead)).to eq('histórico e sino a todos — contrato assinado')
      expect(lead.lead_activities.where(kind: 'zapsign_signed').pluck(:to_value)).to eq(['Contrato'])
      expect(Notification.where(notification_type: 'ramon_contract_status', user: user, primary_actor: lead).count).to eq(1)
    end

    it 'sem selo assinado/recusado não faz nada' do
      expect(rodar('aviso_contrato', create(:lead, account: account)))
        .to eq('contrato: o ZapSign não diz assinado nem recusado (sem status)')
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
    expect(Ramon::Fluxos::Rotinas.alvo('aviso_contrato')).to eq('lead')
  end
end
