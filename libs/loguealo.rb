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
    query = { timestamp: Time.now.to_i }
    query = query.merge! criteria if !criteria.nil?
    options = {
      query: query
    }
    options = options.merge!( generate( uri, options[ :query ]) )
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
