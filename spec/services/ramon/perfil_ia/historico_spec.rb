require 'rails_helper'

# No CI (sem enterprise/) a Account não é auditada: as linhas de auditoria são criadas à mão, como o enterprise grava
# (auditable e associated = a conta, audited_changes['settings'] = [antes, depois]).
RSpec.describe Ramon::PerfilIa::Historico do
  let(:account) { create(:account) }
  let(:tese) { create(:thesis, account: account, name: 'BPC/LOAS') }
  let(:outra) { create(:thesis, account: account) }
  let(:historico) { described_class.new(account) }
  let(:qualificacao) { account.lead_stages.find_by(label: 'fase-qualificacao') }

  def perfis(teses = {}, padrao = Ramon::PerfilIa::INICIAL) = { 'ia_atendimento' => { 'padrao' => padrao, 'teses' => teses } }

  def auditar(antes, depois, conta = account)
    Audited.audit_class.create!(auditable: conta, associated: conta, action: 'update', audited_changes: { 'settings' => [antes, depois] })
  end

  def cfg_da_tese(id) = account.reload.settings.dig('ia_atendimento', 'teses', id.to_s)

  describe '#mudancas' do
    it 'permissão em valor efetivo, com o nome da tese' do
      antes = perfis(tese.id.to_s => { 'base' => 'cautelosa', 'permissoes' => { 'marcar_reuniao' => 'r' } })
      depois = perfis(tese.id.to_s => { 'base' => 'cautelosa', 'permissoes' => { 'marcar_reuniao' => 's' } })

      expect(historico.mudancas(auditar(antes, depois))).to eq(
        [{ alvo: "tese:#{tese.id}", nome_alvo: 'BPC/LOAS', campo: 'permissao', acao_ou_etapa: 'marcar_reuniao',
           de: 'rascunho', para: 'sozinha' }]
      )
    end

    it 'troca de base, Marcador (nome da Etapa), gatilhos e seguir o padrão', :aggregate_failures do
      antes = perfis({ tese.id.to_s => { 'base' => 'cautelosa' }, outra.id.to_s => { 'base' => 'acelerada' } })
      depois = perfis({ tese.id.to_s => { 'base' => 'equilibrada', 'permissoes' => { 'citar_honorario' => 'n' } } },
                      Ramon::PerfilIa::INICIAL.merge('marcador' => '_fim', 'gatilhos' => { 'fase-novo' => %w[pediu_pessoa] }))

      mudancas = historico.mudancas(auditar(antes, depois)).group_by { |m| m[:alvo] }

      # base trocada: o que vem por cima da equilibrada (não cada permissão que a base mudou)
      expect(mudancas["tese:#{tese.id}"].map { |m| m.values_at(:campo, :acao_ou_etapa, :de, :para) }).to eq(
        [['base', nil, 'cautelosa', 'equilibrada'], %w[permissao citar_honorario rascunho nunca]]
      )
      expect(mudancas["tese:#{outra.id}"].map { |m| m.slice(:campo, :de, :para) }).to eq([{ campo: 'segue_padrao', de: false, para: true }])
      padrao = mudancas['padrao'].index_by { |m| m[:campo] }
      expect(padrao['marcador']).to include(de: '_inicio', para: '_fim', nome_alvo: nil)
      expect(padrao['gatilho']).to include(acao_ou_etapa: account.lead_stages.find_by(label: 'fase-novo').name,
                                           para: ['Pediu para falar com uma pessoa'])
      expect(padrao['gatilho'][:de].size).to eq(Ramon::PerfilIa::GATILHOS.size)
    end

    it 'Marcador numa Etapa vai pelo nome; limites e teto no alvo limites' do
      antes = perfis({}, { 'base' => 'cautelosa', 'marcador' => '_inicio' }).merge('ia_limites' => { 'retomadas_dia' => 15 })
      depois = perfis({}, { 'base' => 'cautelosa', 'marcador' => 'fase-qualificacao' })
               .merge('ia_limites' => { 'retomadas_dia' => 25 }, 'ramon_ia_teto_diario_usd' => 3.0)

      expect(historico.mudancas(auditar(antes, depois)).map { |m| m.values_at(:alvo, :campo, :acao_ou_etapa, :de, :para) }).to eq(
        [['padrao', 'marcador', nil, '_inicio', qualificacao.name], ['limites', 'limite', 'retomadas_dia', 15, 25],
         ['limites', 'limite', 'teto_usd', nil, 3.0]]
      )
    end
  end

  describe '#linhas' do
    it 'só as linhas da conta que mexeram no Perfil, nos limites ou no teto' do
      ia = auditar(perfis, perfis(tese.id.to_s => { 'base' => 'acelerada' }))
      auditar({ 'auto_resolve_after' => nil }, { 'auto_resolve_after' => 60 })
      auditar(perfis, perfis(tese.id.to_s => { 'base' => 'acelerada' }), create(:account))

      expect(historico.linhas).to eq([ia])
    end
  end

  describe '#desfazer!' do
    let(:antes) { perfis(tese.id.to_s => { 'base' => 'cautelosa', 'permissoes' => { 'marcar_reuniao' => 'r' } }) }
    let(:depois) do
      perfis(tese.id.to_s => { 'base' => 'cautelosa', 'permissoes' => { 'marcar_reuniao' => 's' } }, outra.id.to_s => { 'base' => 'acelerada' })
    end

    it 'devolve só o alvo da linha; o resto fica como está agora', :aggregate_failures do
      audit = auditar(antes, depois)
      account.update!(settings: depois.deep_merge('ia_atendimento' => { 'padrao' => { 'base' => 'equilibrada' } }))

      historico.desfazer!(audit.id, "tese:#{tese.id}")

      expect(cfg_da_tese(tese.id)).to eq('base' => 'cautelosa', 'permissoes' => { 'marcar_reuniao' => 'r' })
      expect(cfg_da_tese(outra.id)).to eq('base' => 'acelerada')
      expect(account.settings.dig('ia_atendimento', 'padrao', 'base')).to eq('equilibrada')

      historico.desfazer!(audit.id, "tese:#{outra.id}") # não tinha cfg antes = volta a seguir o padrão
      expect(account.reload.settings.dig('ia_atendimento', 'teses').keys).to eq([tese.id.to_s])
    end

    it 'limites: só as chaves que mudaram na linha voltam', :aggregate_failures do
      audit = auditar({ 'ia_limites' => { 'retomadas_dia' => 15 } },
                      { 'ia_limites' => { 'retomadas_dia' => 25 }, 'ramon_ia_teto_diario_usd' => 3.0 })
      account.update!(settings: { 'ia_limites' => { 'retomadas_dia' => 25, 'atraso' => { 'min' => 10, 'max' => 90 } },
                                  'ramon_ia_teto_diario_usd' => 3.0 })

      historico.desfazer!(audit.id, 'limites')

      expect(account.reload.settings['ia_limites']).to eq('retomadas_dia' => 15, 'atraso' => { 'min' => 10, 'max' => 90 })
      expect(account.settings['ramon_ia_teto_diario_usd']).to be_nil
    end

    it 'linha de outra conta ou fora do tipo ia = não encontrada; alvo que não mudou ou valor que não vale mais = recusa',
       :aggregate_failures do
      de_fora = auditar(antes, depois, create(:account))
      sem_ia = auditar({ 'auto_resolve_after' => nil }, { 'auto_resolve_after' => 60 })
      expect { historico.desfazer!(de_fora.id, "tese:#{tese.id}") }.to raise_error(ActiveRecord::RecordNotFound)
      expect { historico.desfazer!(sem_ia.id, 'limites') }.to raise_error(ActiveRecord::RecordNotFound)

      audit = auditar(antes, depois)
      expect { historico.desfazer!(audit.id, 'padrao') }.to raise_error(ArgumentError, /não mudou/)

      etapa_sumiu = auditar(perfis(tese.id.to_s => { 'base' => 'cautelosa', 'marcador' => 'fase-que-sumiu' }), depois)
      expect { historico.desfazer!(etapa_sumiu.id, "tese:#{tese.id}") }.to raise_error(ArgumentError, /marcador desconhecido/)
    end
  end
end
