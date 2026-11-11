require 'rails_helper'

RSpec.describe Ramon::NtfyPushJob do
  let(:account) { create(:account) }
  let(:thesis) { create(:thesis, account: account, name: 'Auxílio-Acidente Teste') }
  let(:lead) { create(:lead, account: account, name: 'João da Silva', thesis: thesis) }

  describe '#perform' do
    context 'when NTFY_TOPIC is set' do
      it 'faz POST pro tópico com título transliterado e corpo com a tese' do
        with_modified_env NTFY_TOPIC: 'ramon-leads' do
          stub = stub_request(:post, 'https://ntfy.sh/ramon-leads')
                 .with(
                   headers: { 'Title' => 'Novo lead', 'Tags' => 'bell' },
                   body: /Auxílio-Acidente/
                 )
                 .to_return(status: 200)

          described_class.perform_now(lead.id)

          expect(stub).to have_been_requested
        end
      end
    end

    context 'when the caller put the lead name in the text' do
      it 'troca o nome pela tese no título e no corpo (o ntfy.sh é público)' do
        with_modified_env NTFY_TOPIC: 'ramon-leads' do
          stub = stub_request(:post, 'https://ntfy.sh/ramon-leads')
                 .with(headers: { 'Title' => 'Reuniao marcada: Auxilio-Acidente Teste' }, body: 'IA: rascunho para Auxílio-Acidente Teste')
                 .to_return(status: 200)

          described_class.perform_now(lead.id, title: 'Reuniao marcada: João da Silva', body: 'IA: rascunho para joão da silva')

          expect(stub).to have_been_requested
        end
      end

      it 'troca também o primeiro nome sozinho e sem acento, sem mexer em palavra que só contém o nome' do
        lead.update!(name: 'Ana João')
        with_modified_env NTFY_TOPIC: 'ramon-leads' do
          stub = stub_request(:post, 'https://ntfy.sh/ramon-leads')
                 .with(body: 'Reunião com Auxílio-Acidente Teste nesta semana; Auxílio-Acidente Teste confirmou')
                 .to_return(status: 200)

          described_class.perform_now(lead.id, title: 'Reuniao marcada', body: 'Reunião com Ana nesta semana; Joao confirmou')

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
