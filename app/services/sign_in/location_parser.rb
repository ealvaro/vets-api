# frozen_string_literal: true

module SignIn
  class LocationParser
    # rubocop:disable ThreadSafety/ClassAndModuleAttributes
    class_attribute :reader_instance, instance_accessor: false, default: nil
    # rubocop:enable ThreadSafety/ClassAndModuleAttributes

    class << self
      def parse(ip)
        new(ip).perform
      end

      def reader
        self.reader_instance ||= build_reader
      end

      private

      def build_reader
        configured = IdentitySettings.sign_in.geolite2&.path
        path = configured.present? ? Rails.root.join(configured).to_s : nil

        unless path && File.exist?(path)
          Rails.logger.info(
            "[SignIn::LocationParser] GeoLite2 database not found at #{path.inspect}; " \
            'IP geolocation will return nil until the database is present.'
          )
          return nil
        end

        MaxMind::GeoIP2::Reader.new(database: path)
      rescue => e
        Rails.logger.info("[SignIn::LocationParser] reader init error: #{e.message}")
        nil
      end
    end

    def initialize(ip)
      @ip = ip
    end

    def perform
      return if ip.blank?
      return unless routable_ip?
      return unless self.class.reader

      city_region
    rescue MaxMind::GeoIP2::AddressNotFoundError
      nil
    rescue => e
      Rails.logger.info("[SignIn::LocationParser] lookup error: #{e.message}")
      nil
    end

    private

    attr_reader :ip

    def routable_ip?
      addr = IPAddr.new(ip)
      !(addr.loopback? || addr.private? || addr.link_local?)
    rescue IPAddr::InvalidAddressError
      false
    end

    def city_region
      record = self.class.reader.city(ip)

      city = record.city&.name.presence
      region = record.most_specific_subdivision&.name.presence

      format_location(city, region)
    end

    def format_location(city, region)
      return if city.blank? && region.blank?
      return city if region.blank?
      return region if city.blank?

      "#{city}, #{region}"
    end
  end
end
