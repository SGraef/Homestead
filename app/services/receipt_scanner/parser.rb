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
    PRICE_RE = /(?<sign>-)?(?<int>\d{1,4})[.,](?<dec>\d{2})/
    LINE_ITEM_RE = /\A(?<name>.+?)\s+(?<sign>-)?(?<int>\d{1,4})[.,](?<dec>\d{2})\b\s*[A-Z]?\s*\z/
    QTY_RE   = /\A(?<qty>\d+(?:[.,]\d+)?)\s*(?:x|X|st[uü]ck|\*)\s*/i

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
      /\b(?<d>\d{1,2})[.\/](?<m>\d{1,2})[.\/](?<y>\d{2,4})\b/,
      /\b(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})\b/
    ].freeze

    # @param raw_text [String]
    # @return [ReceiptScanner::Result]
    def self.parse(raw_text)
      new(raw_text).parse
    end

    def initialize(raw_text)
      @lines = raw_text.to_s.lines
                       .map { |l| l.strip.gsub(/\s{2,}/, " ") }
                       .reject(&:empty?)
    end

    def parse
      Result.new(
        store_name:     detect_store_name,
        purchased_on:   detect_date,
        currency:       "EUR",
        subtotal_cents: detect_total,
        line_items:     detect_line_items
      )
    end

    private

    # Pick the first plausible header line: mostly letters, mostly uppercase,
    # at least 3 chars, doesn't look like a number / date / address.
    def detect_store_name
      @lines.first(6).find do |l|
        l.length.between?(3, 40) &&
          l.match?(/\A[A-ZÄÖÜ][A-ZÄÖÜa-zäöüß0-9 &'\-.]+\z/) &&
          !l.match?(/\d{2}[.\/]\d{2}/) &&
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
      candidates = @lines.select { |l| l.match?(TOTAL_KEYWORDS) }
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
          total_cents:      cents(m)
        )
      end
      items
    end

    def skip_line?(line)
      line.match?(TAX_KEYWORDS) ||
        line.match?(PAYMENT_KEYWORDS) ||
        line.include?("%") ||                                     # tax-rate row
        line.match?(/\A\d+[.\/]\d+/) ||                           # bare date / receipt no
        line.match?(/\b(str|straße|tel|fax|gmbh|http|www)\b/i) || # address / footer
        line.match?(/\A[a-z]\s+\d+[%,.]/i)                        # "A 19% …" / "B 7% …"
    end

    def cents(match)
      sign = match[:sign] == "-" ? -1 : 1
      sign * (match[:int].to_i * 100 + match[:dec].to_i)
    end
  end
end
