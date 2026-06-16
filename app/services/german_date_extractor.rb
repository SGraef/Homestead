# frozen_string_literal: true
# typed: false

# Deterministic German date/time extractor (no NLP gem — Chronic is English-only).
# A small, anchored, explicit-only grammar; precision over recall (a missed date
# beats a junk one). Returns the best Suggestion or nil. The caller resolves the
# date in the household timezone (Suggestion#to_time_in_zone uses Time.zone).
class GermanDateExtractor
  MONTHS = {
    "januar" => 1, "februar" => 2, "märz" => 3, "maerz" => 3, "april" => 4,
    "mai" => 5, "juni" => 6, "juli" => 7, "august" => 8, "september" => 9,
    "oktober" => 10, "november" => 11, "dezember" => 12
  }.freeze
  WEEKDAYS = %w[montag dienstag mittwoch donnerstag freitag samstag sonntag].freeze
  TRIGGERS = %w[termin frist deadline treffen besprechung meeting arzt zahnarzt].freeze

  Suggestion = Struct.new(:date, :hour, :min, :title, :span, keyword_init: true) do
    # Build the start time in the current Time.zone (set by the caller to the
    # household tz). All-day when no time was found.
    def to_time_in_zone
      base = date.in_time_zone
      hour ? base.change(hour: hour, min: min || 0) : base.change(hour: 0)
    end

    def all_day? = hour.nil?
    def span_hash = Digest::SHA256.hexdigest(span.to_s.downcase)
  end

  def self.call(text, reference: Date.current)
    new(text, reference).call
  end

  def initialize(text, reference)
    @text      = text.to_s
    @lower     = @text.downcase
    @reference = reference
  end

  def call
    found = match_date
    return nil unless found

    hour, min = match_time
    Suggestion.new(date: found[:date], hour: hour, min: min, title: build_title, span: found[:span])
  end

  private

  def match_date
    if (m = @lower.match(/\b(?:am\s+)?(\d{1,2})\.\s*(#{MONTHS.keys.join('|')})(?:\s+(\d{4}))?/))
      return safe_date((m[3] || infer_year(MONTHS[m[2]], m[1].to_i)).to_i, MONTHS[m[2]], m[1].to_i, m[0])
    end
    if (m = @lower.match(/\b(\d{1,2})\.(\d{1,2})\.(\d{2,4})?/))
      year = m[3] ? normalize_year(m[3]) : infer_year(m[2].to_i, m[1].to_i)
      return safe_date(year, m[2].to_i, m[1].to_i, m[0])
    end
    return { date: @reference,     span: "heute" }      if @lower.match?(/\bheute\b/)
    return { date: @reference + 2, span: "übermorgen" } if @lower.match?(/\bübermorgen\b/)
    return { date: @reference + 1, span: "morgen" }     if @lower.match?(/\bmorgen\b/)
    if (m = @lower.match(/\b(?:n(?:ä|ae)chsten?\s+|kommenden?\s+)?(#{WEEKDAYS.join('|')})\b/))
      return { date: next_weekday(WEEKDAYS.index(m[1]) + 1), span: m[0] }
    end

    nil
  end

  def match_time
    if (m = @lower.match(/\b(\d{1,2}):(\d{2})\b/)) && valid_time?(m[1].to_i, m[2].to_i)
      return [m[1].to_i, m[2].to_i]
    end
    if (m = @lower.match(/\bum\s+(\d{1,2})(?::(\d{2}))?\s*uhr\b/)) && valid_time?(m[1].to_i, (m[2] || 0).to_i)
      return [m[1].to_i, (m[2] || 0).to_i]
    end

    [nil, nil]
  end

  def valid_time?(hour, min)
    hour.between?(0, 23) && min.between?(0, 59)
  end

  def safe_date(year, month, day, span)
    return nil unless month.between?(1, 12) && day.between?(1, 31)

    { date: Date.new(year, month, day), span: span }
  rescue ArgumentError
    nil
  end

  # No explicit year: use this year, or next year if the date already passed.
  def infer_year(month, day)
    candidate = (Date.new(@reference.year, month, day) rescue nil)
    return @reference.year unless candidate

    candidate < @reference ? @reference.year + 1 : @reference.year
  end

  def normalize_year(str)
    str.length == 2 ? 2000 + str.to_i : str.to_i
  end

  def next_weekday(cwday)
    delta = (cwday - @reference.cwday) % 7
    delta = 7 if delta.zero?
    @reference + delta
  end

  def build_title
    trigger = TRIGGERS.find { |t| @lower.include?(t) }
    trigger ? trigger.capitalize : "Termin"
  end
end
