# frozen_string_literal: true
# typed: true

# Pushes (or removes) a single grocery item to the household's Bring! list.
# Triggered from {GroceryItem} after_commit callbacks; safe to enqueue even
# when no Bring! connection exists (no-ops at the top of `perform`).
class SyncGroceryToBringJob < ApplicationJob
  queue_as :default

  retry_on Bring::Error,           attempts: 3, wait: :polynomially_longer
  discard_on ActiveJob::DeserializationError, ActiveRecord::RecordNotFound, Bring::AuthError

  # @param household_id [Integer]
  # @param action [String, Symbol] :push or :remove
  # @param name [String]
  # @param specification [String, nil]
  def perform(household_id, action:, name:, specification: nil)
    return if name.to_s.strip.empty?

    household  = Household.find(household_id)
    connection = household.bring_connection
    return unless connection&.connected?

    client = Bring::Client.new(connection)
    case action.to_s
    when "push"   then client.push_item(name: name, specification: specification)
    when "remove" then client.remove_item(name: name)
    else
      raise ArgumentError, "Unknown bring action: #{action.inspect}"
    end

    connection.update_columns(last_synced_at: Time.current, last_error: nil, updated_at: Time.current)
  rescue Bring::AuthError => e
    Rails.logger.warn("[Bring] auth error for household=#{household_id}: #{e.message}")
    Household.find_by(id: household_id)&.bring_connection
             &.update_columns(last_error: e.message.first(500), updated_at: Time.current)
    raise
  rescue Bring::Error => e
    Household.find_by(id: household_id)&.bring_connection
             &.update_columns(last_error: e.message.first(500), updated_at: Time.current)
    raise
  end
end
