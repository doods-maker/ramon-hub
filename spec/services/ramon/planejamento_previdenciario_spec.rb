require 'rails_helper'

RSpec.describe Ramon::PlanejamentoPrevidenciario do
  let(:cnis) do
    { 'entrada' => { 'segurado' => { 'nascimento' => '1978-03-10', 'sexo' => 'M' },
                     'competencias' => [{ 'ano' => 2026, 'mes' => 9, 'salario' => '3000.00' }],
                     'vinculos' => [{ 'inicio' => '2010-01-01', 'fim' => nil, 'tipo' => 'CONTRIBUINTE_INDIVIDUAL', 'indicadores' => [] }] },
      'vinculos' => [{ 'seq' => 1, 'origem' => 'EMPRESA FICTICIA', 'remuneracoes' => [] }],
      'uploaded_at' => '2026-11-05T10:00:00-03:00' }
  end

  describe '.payload' do
    it 'monta o corpo do motor com o detalhe dos vínculos e sem campos vazios do perfil' do
      perfil = { 'forma' => 'pro_labore', 'salario_atual' => '3000.00', 'empresa' => 'Empresa Ficticia',
                 'cenario_livre' => '', 'facultativo_semestral' => false, 'descarte_pontos' => 'nao' }
      expect(described_class.payload(cnis, perfil, segurado_nome: 'Fulano de Tal', data_calculo: '2026-11-09')).to eq(
        segurado: cnis['entrada']['segurado'], competencias: cnis['entrada']['competencias'],
        vinculos: cnis['entrada']['vinculos'], vinculos_detalhe: cnis['vinculos'],
        perfil: { 'forma' => 'pro_labore', 'salario_atual' => '3000.00', 'empresa' => 'Empresa Ficticia',
                  'descarte_pontos' => 'nao', 'segurado_nome' => 'Fulano de Tal' },
        data_calculo: '2026-11-09', cnis_data: '2026-11-05'
      )
    end

    it 'sem forma e upload antigo: não manda vinculos_detalhe nem data_calculo' do
      corpo = described_class.payload(cnis.except('vinculos'), {}, segurado_nome: 'X')
      expect(corpo.keys).to match_array(%i[segurado competencias vinculos perfil cnis_data])
      expect(corpo[:perfil]).to eq('segurado_nome' => 'X')
    end

    it 'sem uploaded_at: omite cnis_data' do
      expect(described_class.payload(cnis.except('uploaded_at'), {}, segurado_nome: 'X')).not_to have_key(:cnis_data)
    end
  end

  describe '.nomes' do
    it 'pasta do mês, PDF e memória com o nome saneado' do
      expect(described_class.nomes({ 'nome' => 'Ana / Souza', 'turma' => '' }, hoje: Date.new(2026, 11, 9))).to eq(
        pasta: 'Planejamento previdenciário – 11.26',
        pdf: 'Planejamento previdenciário - Ana Souza.pdf',
        memoria: 'Memória de cálculo - Ana Souza.xlsx'
      )
    end

    it 'com turma o PDF sai como Raio-X Elites' do
      nomes = described_class.nomes({ 'nome' => 'Ana Souza', 'turma' => 'Elites 3' }, hoje: Date.new(2026, 11, 9))
      expect(nomes[:pdf]).to eq('Raio-X Elites - Ana Souza.pdf')
    end
  end
end
