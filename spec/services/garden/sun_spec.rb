# frozen_string_literal: true
# typed: false

require "rails_helper"

# Reference values cross-checked against NOAA's solar calculator for
# Hannover (52.37 N, 9.73 E). Tolerances are generous against the published
# almanac numbers but tight enough to catch any sign/convention slip.
RSpec.describe Garden::Sun do
  let(:lat)  { 52.37 }
  let(:lng)  { 9.73 }
  let(:zone) { ActiveSupport::TimeZone["Europe/Berlin"] }

  describe ".day" do
    context "with the summer solstice" do
      subject(:day) { described_class.day(lat: lat, lng: lng, date: Date.new(2026, 6, 21), zone: zone) }

      it "puts the noon sun at ~61 degrees" do
        expect(day.noon_elevation_deg).to be_within(0.5).of(61.1)
      end

      it "has the sun rising in the northeast and setting in the northwest" do
        expect(day.sunrise_azimuth_deg).to be_within(2).of(48)
        expect(day.sunset_azimuth_deg).to be_within(2).of(312)
      end

      it "matches the almanac clock times (CEST)" do
        expect(day.sunrise).to be_within(10.minutes).of(zone.parse("2026-06-21 05:01"))
        expect(day.sunset).to  be_within(10.minutes).of(zone.parse("2026-06-21 21:42"))
        expect(day.noon).to    be_within(10.minutes).of(zone.parse("2026-06-21 13:22"))
      end
    end

    context "with the winter solstice" do
      subject(:day) { described_class.day(lat: lat, lng: lng, date: Date.new(2026, 12, 21), zone: zone) }

      it "puts the noon sun at ~14 degrees" do
        expect(day.noon_elevation_deg).to be_within(0.5).of(14.2)
      end

      it "has the sun rising in the southeast and setting in the southwest" do
        expect(day.sunrise_azimuth_deg).to be_within(2).of(129)
        expect(day.sunset_azimuth_deg).to be_within(2).of(231)
      end

      it "matches the almanac clock times (CET)" do
        expect(day.sunrise).to be_within(10.minutes).of(zone.parse("2026-12-21 08:31"))
        expect(day.sunset).to  be_within(10.minutes).of(zone.parse("2026-12-21 16:05"))
      end
    end

    context "with the equinox" do
      subject(:day) { described_class.day(lat: lat, lng: lng, date: Date.new(2026, 3, 20), zone: zone) }

      it "has the sun rising almost due east and setting almost due west" do
        expect(day.sunrise_azimuth_deg).to be_within(3).of(89)
        expect(day.sunset_azimuth_deg).to be_within(3).of(271)
      end

      it "puts the noon sun near 90 minus latitude" do
        expect(day.noon_elevation_deg).to be_within(1).of(90 - lat)
      end
    end

    context "with polar latitudes (Svalbard, 78 N)" do
      it "flags polar day in June (no sunrise, sun always up)" do
        day = described_class.day(lat: 78.0, lng: 15.0, date: Date.new(2026, 6, 21), zone: zone)
        expect(day.sunrise).to be_nil
        expect(day).to be_polar_day
      end

      it "flags polar night in December" do
        day = described_class.day(lat: 78.0, lng: 15.0, date: Date.new(2026, 12, 21), zone: zone)
        expect(day.sunrise).to be_nil
        expect(day).to be_polar_night
      end
    end
  end

  describe ".position" do
    it "puts the sun due south at solar noon" do
      noon = described_class.day(lat: lat, lng: lng, date: Date.new(2026, 6, 21), zone: zone).noon
      position = described_class.position(lat: lat, lng: lng, time: noon)
      expect(position[:azimuth_deg]).to be_within(1).of(180)
      expect(position[:elevation_deg]).to be_within(0.5).of(61.1)
    end

    it "reports a below-horizon elevation at midnight" do
      midnight = zone.parse("2026-06-21 00:30")
      expect(described_class.position(lat: lat, lng: lng, time: midnight)[:elevation_deg]).to be_negative
    end
  end

  describe ".key_dates" do
    it "brackets the year with both solstices and the equinox" do
      dates = described_class.key_dates(2026)
      expect(dates.keys).to eq(%i[summer_solstice equinox winter_solstice])
      expect(dates.values).to all(have_attributes(year: 2026))
    end
  end
end
