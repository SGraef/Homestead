# frozen_string_literal: true

FactoryBot.define do
  factory :document do
    household
    user  { association :user }
    title { "Stromrechnung März" }
    status { "stored" }
    kind { "bill" }

    trait(:receipt) { kind { "receipt" } }

    after(:build) do |doc|
      doc.file.attach(
        io:           StringIO.new("%PDF-1.4 fake"),
        filename:     "bill.pdf",
        content_type: "application/pdf"
      )
    end
  end
end
