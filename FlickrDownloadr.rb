require "yaml"
require "dotenv"
require "flickraw"
require "open-uri"
require "fileutils"
require "json"
require "logger"

# json option
class FlickRaw::Response
	def to_h
		to_hash
	end
end

	Dotenv.load
	FlickRaw.api_key=ENV["FLICKR_KEY"]
	FlickRaw.shared_secret=ENV["FLICKR_SECRET"]

	class Retry
		def self.times( n, &block )
			begin
				response = block.call
			rescue => e
				n -= 1
				if n > 0
					retry
				else
					raise e
				end
			end
			response
		end
	end

  class FConfig
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
  
  class FlickrDownloadr
	def initialize to
		@per_page = 500
		@to = to
		@to += "/" unless to[-1] == "/" || to[-1] == "\\" 
		#Dir.mkdir(to) unless Dir.exists?(to)
		@user_id = flickr.test.login.id
	end
	
	def download_year year, logger
		@year = year.to_s
		@logger = logger
		#Dir.mkdir(@to+@year) unless Dir.exists?(@to+@year)
		mn = @year+'-01-01 00:00:00'
		mx = @year+'-12-31 23:59:59'

		page = 0
		i = 0
		list = nil
		begin 
			page += 1
			Retry.times(5) {
				list  = flickr.people.getPhotos( :user_id => @user_id,:min_taken_date => mn, :max_taken_date => mx, :per_page => @per_page, :page => page )
			}
			total = list.total
			if list.count > 0
				list.each do |item|
				    i += 1
					progression = 100.0 * i.to_f / total.to_f
					print "#{year} page #{page}, #{total} photos #{progression.round(1)}%... \r"
					id     = item.id
					secret = item.secret
					info = flickr.photos.getInfo :photo_id => id, :secret => secret
					download_photo info
				end
			end
		end while list.count == @per_page
		puts "#{year} #{page} pages, #{total} photos updated.         "
	end

	private 

	def get_directory info
		# default year wihtout month
		directory = @year
		if info
			taken = info.dates.taken
			if taken 
				directory = taken[0,7].gsub(/-/,'/') 
			end
		end
		directory = @to+directory
		if !Dir.exists?(directory)
			puts "Creating #{directory}...     "
			#Dir.mkdir(directory)
			FileUtils::mkdir_p directory
		end
		directory
	end

	def sanitize filename 
		# sanitize the name based on title
		# Split the name when finding a period which is preceded by some
		# character, and is followed by some character other than a period,
		# if there is no following period that is followed by something
		# other than a period (yeah, confusing, I know)
		fn = filename.split /(?<=.)\.(?=[^.])(?!.*\.[^.])/m

		# We now have one or two parts (depending on whether we could find
		# a suitable period). For each of these parts, replace any unwanted
		# sequence of characters with an underscore
		fn.map! { |s| s.gsub /[^a-z0-9\-]+/i, '_' }       
		#/ 

		# Finally, join the parts with a period and return the result
		fn.join '.'
	end

	def image_name info
		#title = "" == info.title ? info.dates.taken : info.title
		title = info.title
		filename = title + "-" + info.id + "." + info.originalformat
		sanitize filename
	end

	def download from, dest
		begin
			# puts "From: #{from} To: #{dest}"
			# i don't want  https cert problems
			Retry.times(5) {
				open(from.gsub("https:","http:")) {|f|
					File.open(dest,"wb") do |file|
						file.puts f.read
					end
				}
			}
		#rescue Errno::EINVAL => ex
		rescue Exception => ex
			puts ""
			@logger.error "From: [#{from}] To: [#{dest}]"
			@logger.error ex
		end
	end

	def download_photo info
		# get destination location based on image data taken 
		from = FlickRaw.url_o(info)
		dest = get_directory(info) + "/" + image_name(info)
		meta = dest + ".json"
		if !File.exists? meta
			File.open(meta,"wb") do |file|
				file.puts info.to_h.to_json
			end
		end

		if !File.exists? dest
			download from, dest
		end
		# if video
		if info.media == "video"
			sizes = nil
			Retry.times(5) {
				sizes = flickr.photos.getSizes :photo_id => info.id
			}
			original = (sizes.find {|s| s.label == 'Video Original' }).source
			dest = dest.gsub( "." + info.originalformat, ".mp4" )
			if !File.exists? dest
				download original, dest
			end
		end
	end
  end


DOWNLOAD = ENV["DOWNLOAD_DIR"]
puts "FlickrDownloadr by year"
print "Connecting ..."
config = FConfig.new
config.load_config
config.connect unless config.get_username
puts "Ok"

fd = FlickrDownloadr.new( DOWNLOAD )
ARGV.each do|a|
	i = a.to_i
	if i > 999 && i < 10000
		logger = Logger.new File.new("flickr-downloadr-#{a}.log", "a+")
		fd.download_year( i, logger ) 
	end
end
