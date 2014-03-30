module Sinatra
  module Session
    def current_user
      env['warden'].user
    end

    def current_user?
      env['warden'].user.nil? ? false:true
    end
  end
end
