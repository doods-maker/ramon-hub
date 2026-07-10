# frozen_string_literal: true

FactoryBot.define do
  factory :contact do
    sequence(:name) { |n| "Contact #{n}" }
    account

    trait :with_avatar do
      avatar { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }
    end

    trait :with_email do
      sequence(:email) { |n| "contact-#{n}@example.com" }
    end

    trait :with_phone_number do
      phone_number { Faker::PhoneNumber.cell_phone_in_e164 }
    end

    # Ramon fork (LGPD): consentimento de marketing registrado
    trait :with_marketing_consent do
      custom_attributes { { 'consent_marketing' => { 'granted' => true, 'at' => '2026-01-01T00:00:00Z', 'source' => 'manual' } } }
    end
  end
end
