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

    it 'repassa os meses pós-reforma abaixo do mínimo que o /cnis separou' do
      meses = [{ 'ano' => 2020, 'mes' => 11, 'salario' => 900.0, 'minimo' => 1045.0 }]
      com_meses = cnis.deep_dup.tap { |c| c['entrada']['abaixo_minimo_pos_reforma'] = meses }
      expect(described_class.payload(com_meses, {}, segurado_nome: 'X')[:abaixo_minimo_pos_reforma]).to eq(meses)
      expect(described_class.payload(cnis, {}, segurado_nome: 'X')).not_to have_key(:abaixo_minimo_pos_reforma)
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

    it 'tira a barra invertida e os outros caracteres proibidos no Drive' do
      nomes = described_class.nomes({ 'nome' => 'Ana\\Souza: "B" <c>|*?' }, hoje: Date.new(2026, 11, 9))
      expect(nomes[:memoria]).to eq('Memória de cálculo - AnaSouza B c.xlsx')
    end

    it 'textos em rascunho: PDF e memória com o prefixo RASCUNHO, pasta igual' do
      nomes = described_class.nomes({ 'nome' => 'Ana Souza', 'formato_textos' => 'rascunho' }, hoje: Date.new(2026, 11, 9))
      expect(nomes).to eq(
        pasta: 'Planejamento previdenciário – 11.26',
        pdf: 'RASCUNHO - Planejamento previdenciário - Ana Souza.pdf',
        memoria: 'RASCUNHO - Memória de cálculo - Ana Souza.xlsx'
      )
    end

    it 'sem nome: arquivos saem como "Sem nome"' do
      nomes = described_class.nomes({ 'nome' => ' / ' }, hoje: Date.new(2026, 11, 9))
      expect(nomes.values_at(:pdf, :memoria)).to eq(['Planejamento previdenciário - Sem nome.pdf', 'Memória de cálculo - Sem nome.xlsx'])
    end
  end

  describe '#gerar!' do
    let(:motor_url) { 'http://motor:8000' }
    let(:url_recalculo) { "#{motor_url}/planejamento/previdenciario" }
    let(:url_pdf) { "#{motor_url}/planejamento/previdenciario/pdf" }
    let(:account) { create(:account) }
    let(:lead) { create(:lead, account: account, contact: create(:contact, account: account, name: 'Ana Souza')) }
    let(:xlsx) { 'PK xlsx ficticio' }
    let(:dados) do
      { 'nome' => 'Ana Souza', 'turma' => '', 'calculo_data' => '09/11/2026', 'formato_textos' => 'aprovado',
        'aposentadoria' => { 'data' => '10/03/2043', 'frase' => 'texto do motor' },
        'cenarios' => [{ 'nome' => 'Mínimo', 'v' => 1518, 'rmi' => 2234.62, 'sugestao' => true, 'lead' => 'lead editado',
                         'bom' => ['texto editado'] }],
        'parar' => { 'data' => '10/03/2040', 'rmi' => 1518 },
        'pendencias' => [{ 't' => 'Mês sem salário', 'imp' => 'pode tirar tempo', 'p' => 'pendência editada' }] }
    end
    # O que o motor devolve no recálculo: mesmos números (Float onde o front mandou Integer) e os textos originais.
    let(:recalculado) do
      dados.merge('cenarios' => [dados['cenarios'][0].merge('v' => 1518.0, 'lead' => 'lead do motor', 'bom' => ['texto do motor'])],
                  'parar' => { 'data' => '10/03/2040', 'rmi' => 1518.0 },
                  'pendencias' => [dados['pendencias'][0].merge('p' => 'pendência do motor')])
    end
    let(:calculo) do
      Calculo.create!(account: account, lead: lead, tipo: 'planejamento', segurado_nome: 'Ana Souza',
                      snapshot: { 'params' => { 'perfil' => { 'forma' => 'pro_labore' }, 'dados' => dados },
                                  'cnis' => cnis, 'geracao' => { 'estado' => 'gerando' } })
    end

    around { |ex| travel_to(Time.zone.local(2026, 11, 9, 10)) { with_modified_env(MOTOR_CALCULOS_URL: motor_url) { ex.run } } }

    before do
      allow(Ramon::DriveClient).to receive_messages(configured?: true, ensure_folder: 'sub1', substituir: 'arq1')
      allow(Ramon::DriveExportService).to receive(:new).and_return(instance_double(Ramon::DriveExportService, pasta_cliente_id: 'cli1'))
    end

    def stub_recalculo(dados_motor = recalculado)
      corpo = { dados: dados_motor, memoria_xlsx_b64: Base64.strict_encode64(xlsx), forma_sugerida: {}, avisos: [] }
      stub_request(:post, url_recalculo).to_return(status: 200, body: corpo.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    def stub_pdf
      stub_request(:post, url_pdf).to_return(status: 200, body: '%PDF-1.7 ficticio', headers: { 'Content-Type' => 'application/pdf' })
    end

    def geracao = calculo.reload.snapshot['geracao']

    it 'lead com contato: guarda PDF e memória e salva os dois na subpasta do mês' do
      stub_recalculo
      stub_pdf
      described_class.new(calculo).gerar!

      expect(Ramon::DriveClient).to have_received(:ensure_folder).with('Planejamento previdenciário – 11.26', 'cli1')
      expect(Ramon::DriveClient).to have_received(:substituir)
        .with(hash_including(name: 'Planejamento previdenciário - Ana Souza.pdf', content_type: 'application/pdf', parent_id: 'sub1'))
      expect(Ramon::DriveClient).to have_received(:substituir)
        .with(hash_including(name: 'Memória de cálculo - Ana Souza.xlsx', content_type: described_class::XLSX, parent_id: 'sub1'))
      expect(geracao).to eq('estado' => 'pronto', 'drive' => { 'pasta_url' => 'https://drive.google.com/drive/folders/sub1' })
      expect(described_class.arquivo(calculo, 'pdf')).to start_with('%PDF')
      expect(described_class.arquivo(calculo, 'memoria')).to eq(xlsx)
    end

    it 'recalcula com o perfil salvo, o nome e a data do cálculo' do
      stub_recalculo
      stub_pdf
      described_class.new(calculo).gerar!

      corpo = hash_including('data_calculo' => '2026-11-09', 'perfil' => { 'forma' => 'pro_labore', 'segurado_nome' => 'Ana Souza' })
      expect(a_request(:post, url_recalculo).with(body: corpo)).to have_been_made
    end

    it 'manda ao /pdf exatamente o dados editado' do
      stub_recalculo
      stub_pdf
      described_class.new(calculo).gerar!

      expect(a_request(:post, url_pdf).with(body: { dados: dados }.to_json)).to have_been_made
    end

    it 'rascunho sem contato: só download, Drive nem é chamado' do
      lead.update!(contact: nil)
      stub_recalculo
      stub_pdf
      described_class.new(calculo).gerar!

      expect(Ramon::DriveClient).not_to have_received(:ensure_folder)
      expect(geracao).to eq('estado' => 'pronto', 'drive' => nil, 'drive_motivo' => 'sem_cliente')
      expect(described_class.arquivo(calculo, 'pdf')).to start_with('%PDF')
    end

    it 'Drive desligado: só download' do
      allow(Ramon::DriveClient).to receive(:configured?).and_return(false)
      stub_recalculo
      stub_pdf
      described_class.new(calculo).gerar!

      expect(Ramon::DriveClient).not_to have_received(:substituir)
      expect(geracao).to eq('estado' => 'pronto', 'drive' => nil, 'drive_motivo' => 'drive_desligado')
    end

    it 'Drive falha: arquivos continuam para baixar' do
      allow(Ramon::DriveClient).to receive(:substituir).and_raise(Google::Apis::ServerError, 'backendError')
      stub_recalculo
      stub_pdf
      described_class.new(calculo).gerar!

      expect(geracao['estado']).to eq('pronto')
      expect(geracao['drive']).to be_nil
      expect(geracao['drive_erro']).to match(/\Anão salvou no Drive: .*backendError/)
      expect(described_class.arquivo(calculo, 'pdf')).to start_with('%PDF')
    end

    it '422 do motor no PDF vira erro com a mensagem do motor' do
      stub_recalculo
      stub_request(:post, url_pdf).to_return(status: 422, body: { detail: 'o PDF não pôde ser gerado: marcador {data_apx}' }.to_json,
                                             headers: { 'Content-Type' => 'application/json' })
      described_class.new(calculo).gerar!

      expect(geracao['estado']).to eq('erro')
      expect(geracao['erro']).to match(/marcador \{data_apx\}/)
      expect(described_class.arquivo(calculo, 'pdf')).to be_nil
    end

    it '404 do motor vira "motor de cálculos desatualizado"' do
      stub_request(:post, url_recalculo).to_return(status: 404, body: { detail: 'Not Found' }.to_json,
                                                   headers: { 'Content-Type' => 'application/json' })
      described_class.new(calculo).gerar!

      expect(geracao['estado']).to eq('erro')
      expect(geracao['erro']).to match(/\Amotor de cálculos desatualizado/)
    end

    describe 'trava: o recálculo tem de ser o dados da tela, fora os textos editáveis' do
      {
        'rmi de um cenário' => ->(r) { r.merge('cenarios' => [r['cenarios'][0].merge('rmi' => 9999.0)]) },
        'cenarios[0].v' => ->(r) { r.merge('cenarios' => [r['cenarios'][0].merge('v' => 2000.0)]) },
        'nome do cenário (texto do motor)' => ->(r) { r.merge('cenarios' => [r['cenarios'][0].merge('nome' => 'Teto')]) },
        'parar.data' => ->(r) { r.merge('parar' => r['parar'].merge('data' => '10/04/2040')) },
        'formato_textos' => ->(r) { r.merge('formato_textos' => 'rascunho') },
        'texto fora das seções editáveis' => ->(r) { r.merge('aposentadoria' => r['aposentadoria'].merge('frase' => 'outra')) },
        'chave a mais' => ->(r) { r.merge('versao' => 'curta') },
        'item a mais numa seção editável' => ->(r) { r.merge('pendencias' => r['pendencias'] + r['pendencias']) },
        'texto virou número numa seção editável' => ->(r) { r.merge('pendencias' => [r['pendencias'][0].merge('p' => 1)]) }
      }.each do |o_que, mudar|
        it "#{o_que} diferente: erro e não gera PDF" do
          stub_recalculo(mudar.call(recalculado))
          stub_pdf
          described_class.new(calculo).gerar!

          expect(geracao).to eq('estado' => 'erro', 'erro' => 'os números mudaram desde o cálculo — calcule de novo')
          expect(a_request(:post, url_pdf)).not_to have_been_made
        end
      end

      it 'só textos editáveis diferentes (pendência, lead e bom do cenário) e 1518 × 1518.0: gera' do
        stub_recalculo
        stub_pdf
        described_class.new(calculo).gerar!

        expect(geracao['estado']).to eq('pronto')
      end
    end

    it 'textos em rascunho: arquivos no Drive com o prefixo RASCUNHO' do
      dados['formato_textos'] = 'rascunho'
      stub_recalculo
      stub_pdf
      described_class.new(calculo).gerar!

      expect(Ramon::DriveClient).to have_received(:substituir).with(hash_including(name: 'RASCUNHO - Planejamento previdenciário - Ana Souza.pdf'))
      expect(Ramon::DriveClient).to have_received(:substituir).with(hash_including(name: 'RASCUNHO - Memória de cálculo - Ana Souza.xlsx'))
    end

    it 'erro do Drive longo sai cortado em 200 caracteres' do
      allow(Ramon::DriveClient).to receive(:substituir).and_raise(Google::Apis::ServerError, 'x' * 500)
      stub_recalculo
      stub_pdf
      described_class.new(calculo).gerar!

      expect(geracao['drive_erro'].length).to eq('não salvou no Drive: '.length + 200)
    end

    it 'erro inesperado vira "não deu para gerar" com a classe' do
      calculo.update!(snapshot: calculo.snapshot.deep_merge('params' => { 'dados' => { 'calculo_data' => 'ontem' } }))
      described_class.new(calculo).gerar!

      expect(geracao).to eq('estado' => 'erro', 'erro' => 'não deu para gerar: Date::Error')
    end
  end
end
