# frozen_string_literal: true

FactoryBot.define do
  factory :todo do
    household
    sequence(:title) { |n| "Todo #{n}" }
    status { "open" }
  end

  factory :todo_comment do
    todo
    household { todo.household }
    user
    body { "A comment" }
  end
end
