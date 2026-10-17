# frozen_string_literal: true

namespace :ramon do # rubocop:disable Metrics/BlockLength
  namespace :meta do
    desc 'Prova da Meta: envia agora um QualifiedLead do lead com test_event_code (nao grava MetaEvento; funciona com a chave off). ' \
         'Uso: rake "ramon:meta:evento_teste[lead_id,TEST123]"'
    task :evento_teste, %i[lead_id test_event_code] => :environment do |_t, args|
      lead = Lead.find(args[:lead_id])
      referral = lead.custom_attributes.to_h['meta_referral'].to_h
      abort 'lead sem ctwa_clid' if referral['ctwa_clid'].blank?

      waba, token = Ramon::MetaConversaoJob.credenciais(lead, referral)
      abort 'sem canal WhatsApp (token/WABA)' if waba.blank? || token.blank?

      begin
        Ramon::MetaCapi::Cliente.new(token: token, waba_id: waba).enviar(
          evento: 'QualifiedLead', event_id: "teste-#{lead.id}-#{Time.current.to_i}", event_time: Time.current.to_i,
          ctwa_clid: referral['ctwa_clid'], test_event_code: args[:test_event_code]
        )
      rescue StandardError => e
        abort "#{e.class.name}: #{e.message}"
      end
      puts 'ok'
    end

    desc 'Le o gasto por anuncio na Meta agora (ignora a chave RAMON_META_GASTO). Uso: rake "ramon:meta:gasto[7]"'
    task :gasto, [:dias] => :environment do |_t, args|
      abort 'falta RAMON_META_AD_ACCOUNT_ID' if ENV['RAMON_META_AD_ACCOUNT_ID'].blank?

      begin
        linhas = Ramon::MetaGastoJob.new.sincronizar((args[:dias].presence || 7).to_i)
      rescue StandardError => e
        abort e.class.name
      end
      abort 'sem token (RAMON_META_ADS_TOKEN ou canal WhatsApp) ou a Meta recusou' if linhas.nil?
      puts "linhas: #{linhas}"
    end
  end
end
