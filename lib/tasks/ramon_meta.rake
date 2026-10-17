# frozen_string_literal: true

namespace :ramon do
  namespace :meta do
    desc 'Prova da Meta: envia agora um QualifiedLead do lead com test_event_code (nao grava MetaEvento; funciona com a chave off). ' \
         'Uso: rake "ramon:meta:evento_teste[lead_id,TEST123]"'
    task :evento_teste, %i[lead_id test_event_code] => :environment do |_t, args|
      lead = Lead.find(args[:lead_id])
      referral = lead.custom_attributes.to_h['meta_referral'].to_h
      abort 'lead sem ctwa_clid' if referral['ctwa_clid'].blank?

      canal = lead.account.inboxes.find_by(id: referral['inbox_id'])&.channel || lead.conversation&.inbox&.channel
      config = canal.try(:provider_config).to_h
      waba = referral['waba_id'].presence || config['business_account_id']
      abort 'sem canal WhatsApp (token/WABA)' if waba.blank? || config['api_key'].blank?

      begin
        Ramon::MetaCapi::Cliente.new(token: config['api_key'], waba_id: waba).enviar(
          evento: 'QualifiedLead', event_id: "teste-#{lead.id}-#{Time.current.to_i}", event_time: Time.current.to_i,
          ctwa_clid: referral['ctwa_clid'], test_event_code: args[:test_event_code]
        )
      rescue StandardError => e
        abort "#{e.class.name}: #{e.message}"
      end
      puts 'ok'
    end
  end
end
