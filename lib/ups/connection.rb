require 'uri'
require 'excon'
require 'digest/md5'
require 'ox'

module UPS
  class Connection
    attr_accessor :url

    TEST_URL = 'https://wwwcie.ups.com'
    LIVE_URL = 'https://onlinetools.ups.com'

    RATE_PATH = '/ups.app/xml/Rate'
    SHIP_CONFIRM_PATH = '/ups.app/xml/ShipConfirm'
    SHIP_ACCEPT_PATH = '/ups.app/xml/ShipAccept'
    ADDRESS_PATH = '/ups.app/xml/XAV'

    DEFAULT_PARAMS = {
      test_mode: false
    }

    def initialize(params = {})
      params = DEFAULT_PARAMS.merge(params)
      self.url = (params[:test_mode]) ? TEST_URL : LIVE_URL
    end

    def rates(rate_builder = {})
      if rate_builder.empty? && block_given?
        rate_builder = UPS::Builders::RateBuilder.new
        yield rate_builder
      end

      response = get_response_stream RATE_PATH, rate_builder.to_xml
      UPS::Parsers::RatesParser.new.tap do |parser|
        Ox.sax_parse(parser, response)
      end
    end

    def ship
      confirm_builder = Builders::ShipConfirmBuilder.new
      yield confirm_builder if block_given?

      confirm_response = make_confirm_request(confirm_builder)
      if confirm_response.success?
        accept_builder = build_accept_request_from_confirm(confirm_builder,
                                                           confirm_response)
        make_accept_request accept_builder
      else
        confirm_response
      end
    end

    private

    def build_url(path)
      "#{url}#{path}"
    end

    def get_response_stream(path, body)
      response = Excon.post(build_url(path), body: body)
      StringIO.new(response.body)
    end

    def make_confirm_request(confirm_builder)
      confirm_response_stream = get_response_stream SHIP_CONFIRM_PATH,
                                                    confirm_builder.to_xml
      UPS::Parsers::ShipConfirmParser.new.tap do |parser|
        Ox.sax_parse(parser, confirm_response_stream)
      end
    end

    def make_accept_request(accept_builder)
      accept_response = get_response_stream SHIP_ACCEPT_PATH,
                                            accept_builder.to_xml
      UPS::Parsers::ShipAcceptParser.new.tap do |parser|
        Ox.sax_parse(parser, accept_response)
      end
    end

    def build_accept_request_from_confirm(confirm_builder, confirm_response)
      UPS::Builders::ShipAcceptBuilder.new.tap do |builder|
        builder.add_access_request confirm_builder.license_number,
                                   confirm_builder.user_id,
                                   confirm_builder.password
        builder.add_shipment_digest confirm_response.shipment_digest
      end
    end
  end
end
