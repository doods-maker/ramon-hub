require 'rails_helper'

RSpec.describe Ramon::CadernoNoturnoJob do
  it 'so chama o caderno nas contas com a chave ligada', if: ChatwootApp.enterprise? do
    ligada = create(:account, settings: { described_class::CHAVE => true })
    create(:account)
    servico = instance_double(Captain::CadernoNoturno, perform: [])
    allow(Captain::CadernoNoturno).to receive(:new).and_return(servico)

    described_class.perform_now

    expect(Captain::CadernoNoturno).to have_received(:new).with(ligada).once
  end

  it 'uma conta com erro nao derruba as outras', if: ChatwootApp.enterprise? do
    create_list(:account, 2, settings: { described_class::CHAVE => true })
    servico = instance_double(Captain::CadernoNoturno)
    allow(servico).to receive(:perform).and_raise(StandardError, 'quebrou')
    allow(Captain::CadernoNoturno).to receive(:new).and_return(servico)

    expect { described_class.perform_now }.not_to raise_error
    expect(servico).to have_received(:perform).twice
  end

  it 'sem o codigo enterprise nao faz nada', unless: ChatwootApp.enterprise? do
    create(:account, settings: { described_class::CHAVE => true })

    expect { described_class.perform_now }.not_to raise_error
  end
end
