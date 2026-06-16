# frozen_string_literal: true

FactoryBot.define do
  factory :notification do
    household
    user
    kind  { "assigned" }
    title { "You were assigned a todo" }
    sequence(:dedup_key) { |n| "dedup-#{n}" }
  end

  factory :todo_follow do
    todo
    household { todo.household }
    user
  end
end
