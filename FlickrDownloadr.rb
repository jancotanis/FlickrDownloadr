require "dotenv"
require "flickraw"
require "open-uri"
require "fileutils"
require "logger"
require "./flickrawconfig.rb"

	Dotenv.load
	FlickRaw.api_key=ENV["FLICKR_KEY"]
	FlickRaw.shared_secret=ENV["FLICKR_SECRET"]

	class Retry
		def self.times( n, &block )
			begin
				response = block.call
			#rescue OpenURI::HTTPError => e
			rescue => e
				if e.message == '404 Not Found'
					# no retries needed
					raise e
				else
					n -= 1
					if n > 0
						retry
					else
						raise e
					end
				end
			end
			response
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
		count=0
		page = 0
		i = 0
		list = nil
		time_to_go = "??? secs to go"
		start = Time.now
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
					print "#{year} page #{page}, #{total} photos #{progression.round(1)}% #{time_to_go}... \r"
					id     = item.id
					secret = item.secret
					info = flickr.photos.getInfo :photo_id => id, :secret => secret
					info['exif'] = flickr.photos.getExif :photo_id => id, :secret => secret
					download_photo info
					time_to_go = "#{((Time.now - start) * (total.to_i - i) / i).round(0) } secs to go"
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
		title = info.title.empty? ? info.dates.taken : info.title
		#title = info.title
		filename = title + "-" + info.id + "." + info.originalformat
		sanitize filename
	end

	def download from, dest
		begin
			# puts "From: #{from} To: #{dest}"
			Retry.times(5) {
				open(from) {|f|
					File.open(dest,"wb") do |file|
						file.puts f.read
					end
				}
			}
			true
		rescue Exception => ex
			puts ""
			@logger.error "From: [#{from}] To: [#{dest}]"
			@logger.error ex
			false
		end
	end

	def download_photo info
		# get destination location based on image data taken 
		from = FlickRaw.url_o(info)
		dest = get_directory(info) + "/" + image_name(info)
		meta = dest + ".json"
		if !File.exists? meta
			File.open(meta,"wb") do |file|
				file.puts info.to_json
			end
		end

		if !File.exists? dest
			download from.gsub("https:","http:"), dest
		end
		
		if info.media == "video"
			sizes = nil
			Retry.times(5) {
				sizes = flickr.photos.getSizes :photo_id => info.id
			}
			original = (sizes.find {|s| s.label == 'Video Original' }).source
			dest = dest.gsub( "." + info.originalformat, ".mp4" )
			if !File.exists? dest
				if !download(original, dest)
					site = (sizes.find {|s| s.label == 'Site MP4' }).source
					dest = dest.gsub( ".mp4", "-low.mp4" )
					if download(site, dest)
						msg =  "Alternative video downloaded #{site}"
						puts msg
						@logger.info msg
					end
				end
			end
		end
	end
  end


DOWNLOAD = ENV["DOWNLOAD_DIR"]
puts "FlickrDownloadr by year"
print "Connecting ..."
config = FlickrawConfig.new
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
