# frozen_string_literal: true
# typed: true

module ReceiptScanner
  # Heuristic parser that turns raw OCR text into a {ReceiptScanner::Result}.
  #
  # The format of grocery receipts varies wildly between chains and countries.
  # Rather than aim for perfection, we extract the obvious signals (store name
  # at the top, a date somewhere, lines that end in a `12,99` style amount,
  # a final total) and let the user correct the rest in the confirm UI.
  class Parser
    # Bump whenever the parsing heuristics change in a way that could alter the
    # extracted line items. Stamped onto receipts (receipts.parser_version) so a
    # later task can find + re-process receipts parsed by an older version.
    VERSION = 1

    PRICE_RE = /(?<sign>-)?(?<int>\d{1,4})[.,](?<dec>\d{2})/

    # Anchored at end of line with tolerant tail-matching:
    # accepts an optional currency token (€, EUR, OCR-mis-read ¢) and an
    # optional tax-group code -- which in German receipts is usually a
    # bare digit (1 = full VAT, 2 = reduced) but can also be a letter
    # (A/B) or `|` (OCR-miss for 1). Allows a trailing OCR junk char
    # like `]` so a line that ends with a stray bracket still matches.
    LINE_ITEM_RE = /
      \A
      (?<name>.+?)                              # product name (non-greedy)
      \s+
      (?<sign>-)?
      (?<int>\d{1,4})[.,](?<dec>\d{2})          # 12,34 or 12.34
      \s*
      (?:€|EUR|euro?|¢)?                        # optional currency token
      \s*
      (?:[A-Z]|\d|\|)?                          # tax code: A-Z, digit (1 or 2 in DE), or | OCR-miss
      \s*
      [\])]?                                   # tolerate one trailing OCR junk char
      \s*
      \z
    /xi

    QTY_RE = /\A(?<qty>\d+(?:[.,]\d+)?)\s*(?:x|X|st[uü]ck|\*)\s*/i

    # Quantity-hint continuation lines from the OCR ("_ 4x 1,28",
    # "2x 0,89 €", "| 2 x 0,208"). These belong to the previous
    # product line, not their own. The current parser collapses them
    # into a too-short name and drops them anyway, but matching them
    # explicitly here keeps detect_line_items from ever creating a
    # bogus row for them (and gives us a place to fold them into the
    # previous item's unit price later).
    QTY_HINT_LINE_RE = /\A[\s_|]*\d+(?:[.,]\d+)?\s*[xX*]\s*\d/

    # The keyword groups below filter out non-product lines that happen to
    # match the "<name> <amount>" pattern (totals, tax breakdowns, payment
    # rows, etc.). Kept separate so each set can be expanded independently
    # as more receipt formats turn up.
    TOTAL_KEYWORDS = /\b(
      total | summe | gesamt(?:betrag|summe)? | endbetrag | betrag |
      zwischensumme | zw\.?\s?summe | subtotal |
      zu\s?zahlen | zahlbetrag | grand\s?total | amount\s?due
    )\b/ix

    TAX_KEYWORDS = /\b(
      mwst | mehrwertsteuer | ust\.? | umsatzsteuer | steuer |
      vat | tax | netto | brutto | skonto | trinkgeld
    )\b/ix

    PAYMENT_KEYWORDS = /\b(
      bar(?:zahlung)? | wechselgeld | r(?:ü|u)ckgeld | change | gegeben |
      ec[\s-]?karte | giro\s?card | kreditkarte | kartenzahlung |
      visa | mastercard | maestro | paypal | apple\s?pay | google\s?pay |
      bon[-\s]?nr | kassen[-\s]?nr | kunden[-\s]?nr | kassierer
    )\b/ix
    DATE_RES = [
      %r{\b(?<d>\d{1,2})[./](?<m>\d{1,2})[./](?<y>\d{2,4})\b},
      /\b(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})\b/
    ].freeze

    # @param raw_text [String]
    # @param line_confidences [Hash{String=>Integer}] OCR confidence keyed by
    #   raw line text (from the adapter); optional/best-effort.
    # @return [ReceiptScanner::Result]
    def self.parse(raw_text, line_confidences: {})
      new(raw_text, line_confidences: line_confidences).parse
    end

    def initialize(raw_text, line_confidences: {})
      @lines = raw_text.to_s.lines
                       .map { |l| normalize_line(l) }
                       .reject(&:empty?)
      # Re-key the adapter's confidences with the same normalization @lines uses
      # so a parsed line matches its OCR line exactly (normalize_line collapses
      # whitespace, so single-space TSV reconstruction lines up with text mode).
      @confidence_by_line = line_confidences.to_h.transform_keys { |k| normalize_line(k) }
    end

    # Targeted fixes for OCR misreads in the price area. We are
    # deliberately conservative -- substitutions that could plausibly
    # corrupt a real product name are gated on context (digit
    # neighbours).
    def normalize_line(line)
      line.strip
          .gsub(/\s{2,}/, " ")
          .gsub("¢", "€")                  # cent symbol mis-OCR'd for euro
          .gsub(/(?<=\d)°(?=\d)/, ",")     # degree sign mis-OCR'd for comma
    end

    def parse
      Result.new(
        store_name:     detect_store_name,
        purchased_on:   detect_date,
        currency:       "EUR",
        subtotal_cents: detect_total,
        line_items:     detect_line_items,
        parser_version: VERSION
      )
    end

    private

    # Pick the first plausible header line: mostly letters, mostly uppercase,
    # at least 3 chars, doesn't look like a number / date / address.
    def detect_store_name
      @lines.first(6).find do |l|
        l.length.between?(3, 40) &&
          l.match?(/\A[A-ZÄÖÜ][A-ZÄÖÜa-zäöüß0-9 &'\-.]+\z/) &&
          !l.match?(%r{\d{2}[./]\d{2}}) &&
          !l.match?(/\b(str|straße|gmbh|tel|fax|http|www)\b/i)
      end || @lines.first
    end

    def detect_date
      @lines.each do |l|
        DATE_RES.each do |re|
          m = l.match(re)
          next unless m

          year = m[:y].to_i
          year += year < 50 ? 2000 : 1900 if m[:y].length == 2
          begin
            return Date.new(year, m[:m].to_i, m[:d].to_i)
          rescue Date::Error
            next
          end
        end
      end
      nil
    end

    def detect_total
      candidates = @lines.grep(TOTAL_KEYWORDS)
      target = candidates.last
      return nil unless target

      m = target.match(/(?<sign>-)?(?<int>\d{1,4})[.,](?<dec>\d{2})\s*(?:€|EUR)?\s*\z/)
      m && cents(m)
    end

    def detect_line_items
      items = []
      @lines.each_with_index do |line, idx|
        # The first total line is the boundary between products and the
        # receipt's payment / tax footer -- everything below it is noise
        # for our purposes.
        break if line.match?(TOTAL_KEYWORDS)

        next if skip_line?(line)

        m = line.match(LINE_ITEM_RE)
        next unless m

        raw_name = m[:name].strip
        qty_match = raw_name.match(QTY_RE)
        quantity  = qty_match ? qty_match[:qty].tr(",", ".").to_f : 1.0
        name      = qty_match ? raw_name.sub(QTY_RE, "").strip : raw_name
        next if name.length < 2

        items << LineItem.new(
          position:         idx + 1,
          line_text:        line,
          name:             name,
          quantity:         quantity,
          unit_price_cents: nil,
          total_cents:      cents(m),
          confidence:       @confidence_by_line[line]
        )
      end
      items
    end

    def skip_line?(line)
      line.match?(TAX_KEYWORDS) ||
        line.match?(PAYMENT_KEYWORDS) ||
        line.include?("%") || # tax-rate row
        line.match?(%r{\A\d+[./]\d+}) || # bare date / receipt no
        line.match?(/\b(str|straße|tel|fax|gmbh|http|www)\b/i) || # address / footer
        line.match?(/\A[a-z]\s+\d+[%,.]/i) ||                     # "A 19% …" / "B 7% …"
        line.match?(QTY_HINT_LINE_RE) # "_ 4x 1,28", "2x 0,89 €"
    end

    def cents(match)
      sign = match[:sign] == "-" ? -1 : 1
      sign * ((match[:int].to_i * 100) + match[:dec].to_i)
    end
  end
end
