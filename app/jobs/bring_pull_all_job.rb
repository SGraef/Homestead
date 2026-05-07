# frozen_string_literal: true
# typed: true

# Recurring entry point for Bring! pull sync (see config/recurring.yml).
# Fans out into one {BringPullJob} per connected household so each pull
# runs as its own job with its own retry / failure semantics.
class BringPullAllJob < ApplicationJob
  queue_as :default

  def perform
    BringPullJob.sync_all
  end
end
