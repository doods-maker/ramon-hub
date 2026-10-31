require 'rails_helper'

describe Ramon::Peticionamento::Tribunais do
  it { expect(described_class::TODOS['tjsc'][:limite_bytes]).to eq(11 * 1024 * 1024) }
  it { expect(described_class::TODOS['trt12']).to include(sistema: 'pje', limite_bytes: 3 * 1024 * 1024) }
  it { expect(described_class::TIPOS.first).to eq('peticao') }
  it { expect(described_class::TIPOS.last).to eq('outro') }
  it { expect(described_class.tipo_no_tribunal('trf4', 'procuracao')).to eq('PROCURAÇÃO') }
  it { expect(described_class.tipo_no_tribunal('trf4', 'xyz')).to eq('OUTROS') }
  it { expect(described_class.sugerir_tipo('02.1 Procuração assinada.pdf')).to eq('procuracao') }
  it { expect(described_class.sugerir_tipo('Laudo Dr Fulano.PDF')).to eq('laudo_medico') }
  it { expect(described_class.sugerir_tipo('Comprovante de residência.pdf')).to eq('comprovante_residencia') }
  it { expect(described_class.sugerir_tipo('foto.jpg')).to eq('outro') }
end
