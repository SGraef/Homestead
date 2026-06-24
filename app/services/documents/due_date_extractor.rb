# frozen_string_literal: true
# typed: false

module Documents
  # Pulls a *payment due date* out of a bill's OCR text. Unlike
  # {GermanDateExtractor} (which returns the first date anywhere in a string),
  # this is keyword-anchored: it only trusts a date that sits right after a
  # "due"/"zahlbar"/"fällig" phrase, so the invoice date or a service period
  # don't get mistaken for the deadline. Precision over recall -- a missed due
  # date just falls back to the +1-week default in {ProcessDocumentJob}.
  #
  # The actual date parsing is delegated to {GermanDateExtractor} on the slice
  # of text following each keyword, reusing its tested dd.mm.yyyy / "1. März
  # 2026" grammar. Relative spans (heute/morgen/weekday) are rejected -- bills
  # state an explicit calendar date.
  class DueDateExtractor
    # Keywords are matched case-insensitively against the *downcased original*
    # text (umlauts preserved) so the window we hand to GermanDateExtractor
    # still contains umlaut month names like "März".
    KEYWORDS = [
      "zahlbar bis", "zahlbar am", "zahlbar innerhalb",
      "fällig am", "fällig bis", "fälligkeit zum", "fälligkeitsdatum",
      "fälligkeit", "fällig",
      "zahlungsziel", "zahlungstermin", "zahlbar",
      "zu zahlen bis", "bitte überweisen", "überweisung bis",
      "payable by", "due date", "payment due", "due by", "pay by"
    ].freeze
    # How many characters after a keyword to scan for the date.
    WINDOW = 80
    RELATIVE_SPAN = /\A\s*(heute|morgen|übermorgen|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)/i

    # @param text [String] OCR'd document text
    # @param reference [Date] "today" for year inference (household tz)
    # @return [Date, nil]
    def self.call(text, reference: Date.current)
      new(text, reference).call
    end

    def initialize(text, reference)
      @raw       = text.to_s
      @lower     = @raw.downcase
      @reference = reference
    end

    def call
      KEYWORDS.each do |keyword|
        date = date_after(keyword)
        return date if date
      end
      nil
    end

    private

    # First explicit date within WINDOW chars of `keyword`, or nil.
    def date_after(keyword)
      index = @lower.index(keyword)
      return nil unless index

      window = @raw[index, keyword.length + WINDOW].to_s
      suggestion = GermanDateExtractor.call(window, reference: @reference)
      return nil unless suggestion
      return nil if suggestion.span.to_s.match?(RELATIVE_SPAN)

      suggestion.date
    end
  end
end
