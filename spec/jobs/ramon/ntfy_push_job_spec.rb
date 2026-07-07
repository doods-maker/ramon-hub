require 'rails_helper'

RSpec.describe Ramon::NtfyPushJob do
  let(:account) { create(:account) }
  let(:benefit_type) { create(:benefit_type, account: account, name: 'Auxílio-Acidente') }
  let(:lead) { create(:lead, account: account, name: 'João da Silva', benefit_type: benefit_type) }

  describe '#perform' do
    context 'quando NTFY_TOPIC está setado' do
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

    context 'quando NTFY_TOPIC está em branco' do
      it 'não faz nenhuma request' do
        with_modified_env NTFY_TOPIC: '' do
          described_class.perform_now(lead.id)

          expect(a_request(:post, /ntfy\.sh/)).not_to have_been_made
        end
      end
    end

    context 'quando o ntfy falha' do
      it 'não levanta exceção' do
        with_modified_env NTFY_TOPIC: 'ramon-leads' do
          stub_request(:post, 'https://ntfy.sh/ramon-leads').to_raise(Errno::ECONNREFUSED)

          expect { described_class.perform_now(lead.id) }.not_to raise_error
        end
      end
    end
  end
end
