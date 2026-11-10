require 'rails_helper'

describe Ramon::MotorClient do
  let(:motor_url) { 'http://motor:8000' }

  describe '.liquidacao' do
    it 'posts o payload como JSON e devolve o corpo parseado' do
      stub_request(:post, "#{motor_url}/liquidacao")
        .to_return(status: 200, body: { total_geral: '105000.00' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        resultado = described_class.liquidacao({ rmi: '1518.00', dib: '2022-03-10' })
        expect(resultado['total_geral']).to eq('105000.00')
      end
      expect(a_request(:post, "#{motor_url}/liquidacao")
        .with(body: { rmi: '1518.00', dib: '2022-03-10' }.to_json)).to have_been_made
    end

    it 'levanta ValidationError com o detail do motor no 422' do
      stub_request(:post, "#{motor_url}/liquidacao")
        .to_return(status: 422, body: { detail: 'datas fora de ordem: dib <= data_fim <= data_calculo' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        expect { described_class.liquidacao({ rmi: '1.00' }) }
          .to raise_error(described_class::ValidationError, /datas fora de ordem/)
      end
    end

    it 'levanta UnavailableError sem MOTOR_CALCULOS_URL' do
      with_modified_env MOTOR_CALCULOS_URL: nil do
        expect { described_class.liquidacao({}) }.to raise_error(described_class::UnavailableError)
      end
    end
  end

  describe '.liquidacao_pdf' do
    it 'devolve os bytes crus sem parsear' do
      stub_request(:post, "#{motor_url}/liquidacao/pdf")
        .to_return(status: 200, body: '%PDF-1.7 fake', headers: { 'Content-Type' => 'application/pdf' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        expect(described_class.liquidacao_pdf({ rmi: '1518.00' })).to start_with('%PDF')
      end
    end

    it 'levanta ValidationError com o detail do motor no 422' do
      stub_request(:post, "#{motor_url}/liquidacao/pdf")
        .to_return(status: 422, body: { detail: 'dib anterior a 2010 nao suportada' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        expect { described_class.liquidacao_pdf({ rmi: '1.00' }) }
          .to raise_error(described_class::ValidationError, /2010/)
      end
    end

    it 'levanta UnavailableError em HTTP 500' do
      stub_request(:post, "#{motor_url}/liquidacao/pdf").to_return(status: 500, body: 'boom')

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        expect { described_class.liquidacao_pdf({}) }.to raise_error(described_class::UnavailableError)
      end
    end
  end

  describe '.planejamento_previdenciario' do
    let(:url) { "#{motor_url}/planejamento/previdenciario" }
    let(:json) { { 'Content-Type' => 'application/json' } }

    it 'posta o payload e devolve o corpo parseado' do
      stub_request(:post, url)
        .to_return(status: 200, body: { dados: {}, forma_sugerida: { forma: 'pro_labore' } }.to_json, headers: json)

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        expect(described_class.planejamento_previdenciario({ nome: 'X' })['forma_sugerida']['forma']).to eq('pro_labore')
      end
    end

    it 'levanta ValidationError com o detail no 422' do
      stub_request(:post, url)
        .to_return(status: 422, body: { detail: 'vinculos_detalhe inválido' }.to_json, headers: json)

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        expect { described_class.planejamento_previdenciario({}) }
          .to raise_error(described_class::ValidationError, /vinculos_detalhe/)
      end
    end

    it 'levanta UnavailableError "motor de cálculos desatualizado" no 404' do
      stub_request(:post, url).to_return(status: 404, body: { detail: 'Not Found' }.to_json, headers: json)

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        expect { described_class.planejamento_previdenciario({}) }
          .to raise_error(described_class::UnavailableError, /\Amotor de cálculos desatualizado/)
      end
    end
  end

  describe '.planejamento_previdenciario_pdf' do
    let(:url) { "#{motor_url}/planejamento/previdenciario/pdf" }

    it 'manda {dados:} e devolve os bytes crus' do
      stub_request(:post, url)
        .to_return(status: 200, body: '%PDF-1.7 fake', headers: { 'Content-Type' => 'application/pdf' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        expect(described_class.planejamento_previdenciario_pdf({ 'nome' => 'X' })).to start_with('%PDF')
      end
      expect(a_request(:post, url).with(body: { dados: { nome: 'X' } }.to_json)).to have_been_made
    end

    it 'levanta ValidationError no 422' do
      stub_request(:post, url)
        .to_return(status: 422, body: { detail: 'o PDF não pôde ser gerado: marcador' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      with_modified_env MOTOR_CALCULOS_URL: motor_url do
        expect { described_class.planejamento_previdenciario_pdf({}) }
          .to raise_error(described_class::ValidationError, /marcador/)
      end
    end
  end
end
