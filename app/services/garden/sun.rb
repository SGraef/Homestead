# frozen_string_literal: true
# typed: false

module Garden
  # Solar geometry for the Grundstücksplan, via the NOAA "General Solar
  # Position Calculations" equations (Fourier-series equation of time and
  # declination). Accuracy is a few arc-minutes / about a minute of clock
  # time -- far tighter than what garden planning needs, with no gem and no
  # ephemeris data.
  #
  # Conventions: azimuth in degrees clockwise from true north (0 = N,
  # 90 = E, 180 = S), elevation in degrees above the horizon.
  module Sun
    # Sun below this true elevation counts as set: 50 arc-minutes account for
    # atmospheric refraction (34') plus the radius of the solar disc (16').
    HORIZON_ELEVATION_DEG = -0.833

    # One day of sun at one place: rise/set clock times with the compass
    # direction the sun stands in, and the highest point of the day.
    Day = Struct.new(:date, :sunrise, :sunset, :sunrise_azimuth_deg,
                     :sunset_azimuth_deg, :noon, :noon_elevation_deg,
                     keyword_init: true) do
      def polar_night? = sunrise.nil? && noon_elevation_deg <= HORIZON_ELEVATION_DEG
      def polar_day?   = sunrise.nil? && noon_elevation_deg > HORIZON_ELEVATION_DEG
    end

    class << self
      # Azimuth + elevation of the sun at an instant.
      # @param lat [Float]
      # @param lng [Float] east-positive
      # @param time [Time] any zone; internally converted to UTC
      # @return [Hash] { azimuth_deg:, elevation_deg: }
      def position(lat:, lng:, time:)
        utc = time.utc
        decl, eqtime = declination_and_eqtime(utc)

        # True solar time in minutes: clock UTC corrected by longitude and
        # the equation of time. Hour angle: 0 at solar noon, +15°/h after.
        tst  = (utc.hour * 60.0) + utc.min + (utc.sec / 60.0) + (4.0 * lng) + eqtime
        ha   = rad((tst / 4.0) - 180.0)
        phi  = rad(lat)

        cos_zenith = (Math.sin(phi) * Math.sin(decl)) +
                     (Math.cos(phi) * Math.cos(decl) * Math.cos(ha))
        zenith = Math.acos(cos_zenith.clamp(-1.0, 1.0))

        azimuth = azimuth_from(phi, decl, zenith, ha)
        { azimuth_deg: azimuth.round(1), elevation_deg: (90.0 - deg(zenith)).round(1) }
      end

      # The full sun picture for one calendar date.
      # @param lat [Float]
      # @param lng [Float]
      # @param date [Date]
      # @param zone [ActiveSupport::TimeZone] for the returned clock times
      # @return [Day] sunrise/sunset are nil during polar day/night
      def day(lat:, lng:, date:, zone:)
        noon_guess = zone.local(date.year, date.month, date.day, 12).utc
        decl, eqtime = declination_and_eqtime(noon_guess)

        solar_noon_utc = utc_minutes_to_time(date, 720.0 - (4.0 * lng) - eqtime)
        noon_elev = position(lat: lat, lng: lng, time: solar_noon_utc)[:elevation_deg]

        ha_deg = sunrise_hour_angle_deg(rad(lat), decl)
        return Day.new(date: date, noon: solar_noon_utc.in_time_zone(zone), noon_elevation_deg: noon_elev) unless ha_deg

        sunrise_utc = utc_minutes_to_time(date, 720.0 - (4.0 * (lng + ha_deg)) - eqtime)
        sunset_utc  = utc_minutes_to_time(date, 720.0 - (4.0 * (lng - ha_deg)) - eqtime)

        Day.new(
          date:                date,
          sunrise:             sunrise_utc.in_time_zone(zone),
          sunset:              sunset_utc.in_time_zone(zone),
          sunrise_azimuth_deg: position(lat: lat, lng: lng, time: sunrise_utc)[:azimuth_deg],
          sunset_azimuth_deg:  position(lat: lat, lng: lng, time: sunset_utc)[:azimuth_deg],
          noon:                solar_noon_utc.in_time_zone(zone),
          noon_elevation_deg:  noon_elev
        )
      end

      # The three days that bracket a year of sun: highest arc, mean arc,
      # lowest arc. What a bed sees between the June and December extremes is
      # everything it will ever see.
      # @param year [Integer]
      # @return [Hash{Symbol => Date}]
      def key_dates(year)
        {
          summer_solstice: Date.new(year, 6, 21),
          equinox:         Date.new(year, 3, 20),
          winter_solstice: Date.new(year, 12, 21)
        }
      end

      private

      # Solar declination (radians) and equation of time (minutes) from the
      # fractional year -- NOAA's Fourier expansions.
      def declination_and_eqtime(utc)
        gamma = 2.0 * Math::PI / 365.0 *
                (utc.yday - 1 + ((utc.hour - 12) / 24.0))

        eqtime = 229.18 * (0.000075 +
          (0.001868 * Math.cos(gamma)) - (0.032077 * Math.sin(gamma)) -
          (0.014615 * Math.cos(2 * gamma)) - (0.040849 * Math.sin(2 * gamma)))

        decl = 0.006918 -
               (0.399912 * Math.cos(gamma)) + (0.070257 * Math.sin(gamma)) -
               (0.006758 * Math.cos(2 * gamma)) + (0.000907 * Math.sin(2 * gamma)) -
               (0.002697 * Math.cos(3 * gamma)) + (0.00148 * Math.sin(3 * gamma))

        [decl, eqtime]
      end

      # Half the daylight arc in degrees, or nil when the sun never crosses
      # the horizon that day (polar day/night).
      def sunrise_hour_angle_deg(phi, decl)
        cos_ha = (Math.cos(rad(90.0 - HORIZON_ELEVATION_DEG)) /
                  (Math.cos(phi) * Math.cos(decl))) -
                 (Math.tan(phi) * Math.tan(decl))
        return nil unless cos_ha.between?(-1.0, 1.0)

        deg(Math.acos(cos_ha))
      end

      # Azimuth measured clockwise from north; the hour-angle sign says
      # whether the sun is east (morning) or west (afternoon) of the meridian.
      def azimuth_from(phi, decl, zenith, hour_angle)
        denominator = Math.cos(phi) * Math.sin(zenith)
        return 180.0 if denominator.abs < 1e-9 # sun at zenith/nadir: undefined, pick south

        cos_az = ((Math.sin(phi) * Math.cos(zenith)) - Math.sin(decl)) / denominator
        azimuth = 180.0 - deg(Math.acos(cos_az.clamp(-1.0, 1.0)))
        Math.sin(hour_angle).positive? ? (360.0 - azimuth) % 360.0 : azimuth
      end

      def utc_minutes_to_time(date, minutes)
        Time.utc(date.year, date.month, date.day) + (minutes * 60).round
      end

      def rad(degrees) = degrees * Math::PI / 180.0
      def deg(radians) = radians * 180.0 / Math::PI
    end
  end
end
