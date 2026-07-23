require 'rails_helper'

RSpec.describe Ramon::NtfyPushJob do
  let(:account) { create(:account) }
  let(:benefit_type) { create(:benefit_type, account: account, name: 'Auxílio-Acidente') }
  let(:lead) { create(:lead, account: account, name: 'João da Silva', benefit_type: benefit_type) }

  describe '#perform' do
    context 'when NTFY_TOPIC is set' do
      it 'faz POST pro tópico com título transliterado e corpo com o benefício' do
        with_modified_env NTFY_TOPIC: 'ramon-leads' do
          stub = stub_request(:post, 'https://ntfy.sh/ramon-leads')
                 .with(
                   headers: { 'Title' => 'Novo lead: Joao da Silva', 'Tags' => 'bell' },
                   body: /Auxílio-Acidente/
                 )
                 .to_return(status: 200)

          described_class.perform_now(lead.id)

          expect(stub).to have_been_requested
        end
      end
    end

    context 'when NTFY_TOPIC is blank' do
      it 'não faz nenhuma request' do
        with_modified_env NTFY_TOPIC: '' do
          described_class.perform_now(lead.id)

          expect(a_request(:post, /ntfy\.sh/)).not_to have_been_made
        end
      end
    end

    context 'without a lead (resumo diário)' do
      it 'posta com título ASCII (· vira -) e o corpo dado' do
        with_modified_env NTFY_TOPIC: 'ramon-leads' do
          stub = stub_request(:post, 'https://ntfy.sh/ramon-leads')
                 .with(headers: { 'Title' => 'Ramon Hub - seu dia' }, body: '3 tarefas vencidas · R$ 391 mil em jogo')
                 .to_return(status: 200)

          described_class.perform_now(title: 'Ramon Hub · seu dia', body: '3 tarefas vencidas · R$ 391 mil em jogo')

          expect(stub).to have_been_requested
        end
      end

      it 'sem título ou corpo não faz request' do
        with_modified_env NTFY_TOPIC: 'ramon-leads' do
          described_class.perform_now(title: 'Só título')

          expect(a_request(:post, /ntfy\.sh/)).not_to have_been_made
        end
      end
    end

    context 'when ntfy fails' do
      it 'não levanta exceção' do
        with_modified_env NTFY_TOPIC: 'ramon-leads' do
          stub_request(:post, 'https://ntfy.sh/ramon-leads').to_raise(Errno::ECONNREFUSED)

          expect { described_class.perform_now(lead.id) }.not_to raise_error
        end
      end
    end
  end
end
