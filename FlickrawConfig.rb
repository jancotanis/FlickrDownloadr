require "yaml"
require "flickraw"
require "json"

	# json option
	class FlickRaw::Response
		def to_json
			 JSON.pretty_generate eval(self.to_hash.to_s)
		end
		def []=(k,v)
			@h[k]=v 
		end
	end

	class FlickrawConfig
		CONFIG_FILENAME = "./config.yml"

		def initialize
		  if File.exists?(CONFIG_FILENAME)
			file = File.open(CONFIG_FILENAME, "r")
			@config = YAML.load(file.read)

			unless @config && @config[:access_token] && @config[:access_token_secret]
			  raise "Problem with config.yml. Please delete the file and try to connect again."
			end

			file.close
		  else
			@config = {
			  :access_token => nil,
			  :access_token_secret => nil,
			}
		  end
		end

		def connect
		  if load_config && username = get_username
			puts "You already have the Flickr account '#{username}' connected."
			puts "Do you want to connect a new account? [y/n]"
			input = gets.chomp

			return if input.match(/n/i)
		  end

		  authenticate
		end

		def load_config
		  return false unless @config[:access_token] && @config[:access_token_secret]

		  flickr.access_token = @config[:access_token]
		  flickr.access_secret = @config[:access_token_secret]

		  self
		end

		def get_username
		  begin
			return flickr.test.login.username
		  rescue FlickRaw::OAuthClient::FailedResponse
			return false
		  end
		end

		private

		def authenticate
		  puts "Authenticating with Flickr ..."
		  token = flickr.get_request_token
		  #auth_url = flickr.get_authorize_url(token['oauth_token'], :perms => 'delete')
		  auth_url = flickr.get_authorize_url(token['oauth_token'])

		  puts "Open the following url in your browser and approve the application"
		  puts auth_url
		  puts "Then copy here the number given in the browser and press enter (cmd props legacy console):"
		  verify = gets.strip

		  begin
			flickr.get_access_token(token['oauth_token'], token['oauth_token_secret'], verify)
			login = flickr.test.login
			puts "You are now authenticated as #{login.username} with token #{flickr.access_token} and secret #{flickr.access_secret}"
		  rescue FlickRaw::FailedResponse => e
			puts "Authentication failed : #{e.msg}"
			return
		  end

		  @config[:access_token] = flickr.access_token
		  @config[:access_token_secret] = flickr.access_secret

		  write_config
		end

		def write_config
		  file = File.open(CONFIG_FILENAME, "w")
		  file.puts(YAML.dump(@config))
		  file.close
		end
	end
