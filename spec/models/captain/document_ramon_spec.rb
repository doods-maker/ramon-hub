require 'rails_helper'

# FORK-PONTO (ramon): documento com conteudo colado direto (sem link nem PDF).
# Depende do codigo enterprise (o CI FOSS remove a pasta), por isso o guard.
RSpec.describe 'Captain::Document com conteudo direto', type: :model, if: ChatwootApp.enterprise? do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }

  it 'nasce available, com link placeholder TEXT: e sem CrawlJob' do
    document = nil
    expect do
      document = Captain::Document.create!(assistant: assistant, account: account, name: 'Playbook', content: 'Texto do playbook')
    end.not_to have_enqueued_job(Captain::Documents::CrawlJob)

    expect(document).to be_available
    expect(document.external_link).to start_with('TEXT: Playbook')
    expect(document).not_to be_syncable
    expect(Captain::Document.syncable).not_to include(document)
  end

  it 'dispara o ResponseBuilderJob com o conteudo' do
    expect do
      Captain::Document.create!(assistant: assistant, account: account, name: 'Playbook', content: 'Texto do playbook')
    end.to have_enqueued_job(Captain::Documents::ResponseBuilderJob)
  end

  it 'continua exigindo external_link quando nao ha conteudo nem PDF' do
    document = Captain::Document.new(assistant: assistant, account: account, name: 'Vazio')
    expect(document).not_to be_valid
  end
end
