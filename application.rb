require 'open-uri'
require 'bcrypt'
require 'json'
require 'xmlsimple'
require 'dragonfly'
require 'mongoid' 
require 'redis' 
require 'rack-flash'
require 'warden' 
require 'sinatra'
require "sinatra/reloader"
require './libs/loguealo'
require './helpers/sessions'
require './models/user'

Mongoid.load!( 'config/mongoid.yml' )

Dragonfly.app.configure do
  plugin :imagemagick
end

LOGUEALO ||= Loguealo.new( 'eba6fa57ae1a4a8ca31ea3f7bcb14e93', '6c73edc5cd465f62573dcfe3b96f46f386afac75107c062d77fd7969b715d99a', 'http://0c433c11db109938a7d8a5a99e1d7f88.loguealo.com' )

configure :development do
  register Sinatra::Reloader
  REDIS = Redis.new( :host => 'localhost', :port => '6379', :password => 'foobared' )
end
configure :production do
  uri = URI.parse(ENV["REDISTOGO_URL"])
  REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
end


use Rack::Session::Cookie, secret: "__app_homepage"
use Rack::Flash

use Warden::Manager do |config|
  config.default_scope = :user
  config.failure_app = self

  config.scope_defaults :user, strategies: [ :password ]
end

Warden::Manager.before_failure do |env,opts|
  env['REQUEST_METHOD'] = 'POST'
end

Warden::Strategies.add(:password) do
  def valid?
    params['user'] && params['user']['username'] && params['user']['password']
  end

  def authenticate!
    response =  LOGUEALO.get email: params['user']['username']
    if response.code == 404
      fail!( 'Could not log in' )

    else
      account = JSON.parse( response.body )[ 'account' ]

      password = BCrypt::Engine.hash_secret(params['user']['password'], account['salt'])
      account[ 'password' ] == password ? success!( account ) : fail!( 'Password incorrect' )
    end
  end
end




get '/users/new/?' do
  haml 'users/new'.to_sym
end

get '/sessions/new' do
  haml 'sessions/new'.to_sym
end

delete '/sessions/?' do
  env['warden'].raw_session.inspect
  env['warden'].logout
  redirect '/'
end

post '/sessions' do
  env['warden'].authenticate!

  #flash.success = env['warden'].message

  if session[:return_to].nil?
    redirect '/'
  else
    redirect session[:return_to]
  end
end

get '/' do
  stories_json = []
  stories = REDIS.zrevrange 'feeds:stories', 0, 50
  stories.each_with_index do | story, key |
    #do i like it?
    story_data = JSON.parse(REDIS.get(sprintf('stories:%s', story)))
    if current_user?
      like = REDIS.sismember( sprintf( 'users:%s:likes', current_user['id']['$oid'] ), story )
      hstory = story_data[0].merge!({ like: like })
    else
      hstory = story_data[0]
    end

    nlikes = REDIS.get sprintf( 'stories:%s:likes', hstory['id'] )
    hstory.merge!({ nlikes: ( nlikes.nil? ? 0:nlikes ) })

    stories_json.push hstory
  end
  #puts stories_json
  haml :index, locals: { news: stories_json }
end

get '/stories/:id' do
  params[:id]
  story = REDIS.get sprintf 'stories:%s', params[:id]
  halt 404 if story.nil?

  story_key = sprintf 'stories:%s:score', params[:id] 
  score = REDIS.get story_key
  if score.nil?
    REDIS.set story_key, 1
  else
    REDIS.incr  story_key
  end

  story = JSON.parse story
  redirect story[0][ 'url' ]
end

get '/images/' do
  puts params[:url]
  Dragonfly.app.fetch_url( params[:url] ).thumb('238x').to_response(env)
end

post '/users/?' do
  password_salt = BCrypt::Engine.generate_salt
  password_hash = BCrypt::Engine.hash_secret(params[:user][:password], password_salt)
  user = params[:user].except 'password', 'password_confirmation'
  user = user.merge! password: password_hash, salt: password_salt

  begin
    response = LOGUEALO.post profile: 'user', account: user
    if response.code == 400
      puts 'we have an error'
      puts response.body
      'Error'
    else response.code == 200
      redirect '/sessions/new'
    end
  rescue Exception => e
    puts 'ERROR'
    puts e
  end
end

post '/loguealo/new/?' do
  account = JSON.parse( request.body.read )[ 'account' ]
  account_id = account[ 'id' ][ '$oid' ]
  user = REDIS.hlen(sprintf('users:%s', account_id ))
  if user <= 0
    REDIS.hmset( sprintf( 'users:%s', account_id ), 'name', account[ 'name' ], 'id', account_id )
  end
end

post '/stories/:id/?' do
  env['warden'].authenticate!

  story_id = params[ :id ]
  user_id = current_user[ 'id' ][ '$oid']
  likes_key = sprintf( 'users:%s:likes', user_id )

  member = REDIS.sismember likes_key, params[ :id ]
  if !member
    puts 'create the member'

    #basic set
    REDIS.sadd likes_key, story_id
    REDIS.incr sprintf( 'stories:%s:likes', story_id )

    #plus score
    score = REDIS.zscore 'feed:likes', story_id
    if score.nil?
      story_key = REDIS.zcard 'feed:likes'
      REDIS.zadd 'feed:likes', story_key, story_id
    else
      REDIS.zincrby 'feed:likes', score, story_id
    end
  end
  redirect '/'
end

post '/unauthenticated/?' do
  session[:return_to] = env['warden.options'][:attempted_path]
  redirect '/sessions/new'
end
