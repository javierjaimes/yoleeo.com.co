require 'httparty'

DIGEST ||= OpenSSL::Digest::Digest.new('sha256')

class Loguealo
  include HTTParty

  def initialize(u, p, uri)
    @auth = {:client => u, :secret => p}
    self.class.base_uri uri
  end

  def get criteria = nil
    uri = '/'
    options = {}

    if criteria.is_a?(Hash)
      query = { timestamp: Time.now.to_i }
      query = query.merge! criteria 
      options = {
        query: query
      }
      options = options.merge!( generate( uri, options[ :query ]) )
    elsif !criteria.nil?
      uri = sprintf( '%s%s', uri, criteria )
      query = { timestamp: Time.now.to_i }
      options = {
        query: query
      }
      options = options.merge!( generate( uri, options[ :query ]) )
    end

    self.class.get uri, options
  end

  def post data
    uri = '/'
    options = {
      query: {
        timestamp: Time.now.to_i
      }
    }
    options = options.merge!( body: data )
    options = options.merge!( generate( uri, options[ :query ]) )
    self.class.post( uri, options )
  end

  private
    def generate uri, query
      params = query.sort.map{|k,v| "#{k}=#{v}"}.join('&')
      { 
        basic_auth: {
          username: @auth[ :client ],
          password: Base64.encode64(OpenSSL::HMAC.digest(DIGEST, @auth[ :secret ], [ uri, params ].join('?') ))
        }
      }
    end
end
