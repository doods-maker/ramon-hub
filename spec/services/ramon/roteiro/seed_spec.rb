require 'rails_helper'
require 'tmpdir'

RSpec.describe Ramon::Roteiro::Seed do
  let(:account) { create(:account) }
  let(:dir) { Dir.mktmpdir }
  let(:passos) { RoteiroPasso.where(account: account) }

  def arquivo(nome, conteudo) = File.write(File.join(dir, nome), conteudo)
  def semear = Ramon::Roteiro::Seed.new(account, dir: dir).run

  before do
    arquivo('comuns.yml', <<~YAML)
      tese: null
      passos:
        - chave: tem_advogado
          titulo: "Tem advogado"
          tipo_resposta: sim_nao
          saidas:
            - { id: sim, quando: "sim", acao: desqualificar, motivo: "tem advogado", efeitos: { etiqueta: "TemAdvogado" } }
            - { id: nao, quando: "nao", acao: seguir }
    YAML
    arquivo('bpc.yml', <<~YAML)
      tese: "BPC/LOAS (idoso ou pessoa com deficiência)"
      antes: ["BPC/LOAS por deficiência"]
      passos:
        - chave: recebe_beneficio
          titulo: "Já recebe benefício"
          tipo_resposta: sim_nao
          saidas:
            - { id: sim, quando: "sim", acao: ir_para, alvo: renda }
            - { id: nao, quando: "nao", acao: seguir }
        - { chave: renda, titulo: "Renda", tipo_resposta: numero }
    YAML
    arquivo('nova.yml', <<~YAML)
      tese: "Tese nova do seed"
      passos:
        - { chave: situacao, titulo: "Situação", tipo_resposta: texto }
    YAML
  end

  after { FileUtils.remove_entry(dir) }

  it 'cria os passos na ordem do arquivo, renomeia a tese pelo nome antigo (mesmo id) e cria a que falta' do
    bpc_id = account.theses.find_by!(name: 'BPC/LOAS por deficiência').id

    expect(semear).to include(passos_criados: 4, teses_criadas: 1)
    expect(account.theses.find(bpc_id).name).to eq('BPC/LOAS (idoso ou pessoa com deficiência)')
    expect(passos.where(thesis_id: bpc_id).pluck(:chave, :position)).to eq([['recebe_beneficio', 0], ['renda', 1]])
    expect(passos.comuns.pluck(:chave)).to eq(['tem_advogado'])
    expect(account.theses.find_by!(name: 'Tese nova do seed')).to have_attributes(honorario_na_tabela: false, area: 'previdenciario')
    expect(account.labels.pluck(:title)).to include('temadvogado', 'desqualificado-ia')
  end

  # Review Focus 1.
  it 'rodar de novo não duplica, devolve o texto do arquivo ao passo não editado e pula o editado na tela' do
    semear
    passos.find_by!(chave: 'renda').update!(titulo: 'Mexido no console', opcoes: ['x'])
    passos.find_by!(chave: 'tem_advogado').update!(titulo: 'Editado na tela', edited: true)

    expect(semear).to include(passos_atualizados: 3, passos_pulados_editados: 1)
    expect(passos.count).to eq(4)
    expect(passos.find_by!(chave: 'renda')).to have_attributes(titulo: 'Renda', opcoes: [])
    expect(passos.find_by!(chave: 'tem_advogado').titulo).to eq('Editado na tela')
    expect(account.theses.where(name: 'Tese nova do seed').count).to eq(1)
  end

  # Review Focus 2.
  it 'roteiro com "vai para" sem destino não grava nada, nem tese criada ou renomeada' do
    arquivo('quebrado.yml', <<~YAML)
      tese: "Tese quebrada"
      passos:
        - chave: primeiro
          titulo: "Primeiro"
          tipo_resposta: sim_nao
          saidas: [{ id: sim, quando: "sim", acao: ir_para, alvo: nao_existe }]
    YAML

    expect { semear }.to raise_error(ArgumentError, /primeiro: .*nao_existe/)
    expect(passos.count).to eq(0)
    expect(account.theses.where(name: ['Tese quebrada', 'Tese nova do seed']).count).to eq(0)
    expect(account.theses.where(name: 'BPC/LOAS por deficiência').count).to eq(1)
  end
end
