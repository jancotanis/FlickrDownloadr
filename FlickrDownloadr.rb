require "dotenv"
require "flickraw"
require "open-uri"
require "fileutils"
require "logger"
require "./flickrawconfig.rb"

PREVIEW_EXT = ".jpg"
MOVIE_EXT = ".mp4"
LQ_EXT = "-low.mp4"	

	Dotenv.load
	FlickRaw.api_key=ENV["FLICKR_KEY"]
	FlickRaw.shared_secret=ENV["FLICKR_SECRET"]
	HTTP404 = '404 Not Found'

	class Retry
		def self.times( n, &block )
			begin
				response = block.call
			#rescue OpenURI::HTTPError => e
			rescue => e
				if e.message == HTTP404
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
		@user_id = flickr.test.login.id
		@set_ids = nil
	end
	
	def download_set set, logger
		@logger = logger
		@set_ids ||= get_sets
		id = @set_ids[set]
		if id
			puts "Downloading set [#{set}]/[#{id}]" 
			count=0
			page = 0
			i = 0
			list = nil
			response = nil
			time_to_go = "??? secs to go"
			start = Time.now
			begin 
				page += 1
				Retry.times(5) {
					response  = flickr.photosets.getPhotos( :photoset_id => id,:user_id => @user_id, :per_page => @per_page, :page => page )
					list = response.photo
				}
				total = response.total
				download_list( list ) {
					if (i != 0)
						time_to_go = "#{((Time.now - start) * (total.to_i - i) / i).round(0)} secs to go"
					end
					i += 1
					progression = 100.0 * i.to_f / total.to_f
					print "#{set} page #{page}, #{total} photos #{progression.round(1)}% #{time_to_go}... \r"
				}
			end while list.count == @per_page
			puts "#{set} #{page} pages, #{total} photos updated.         "
		else
			puts "Photoset [#{set}] not found"
		end
	end

	def download_year year, logger
		@year = year.to_s
		@logger = logger
		mn = @year+'-01-01 00:00:00'
		mx = @year+'-12-31 23:59:59'
		count = 0
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
			download_list( list ) {
				if (i != 0)
					time_to_go = "#{((Time.now - start) * (total.to_i - i) / i).round(0) } secs to go"
				end
				i += 1
				progression = 100.0 * i.to_f / total.to_f
				print "#{year} page #{page}, #{total} photos #{progression.round(1)}% #{time_to_go}... \r"
			}
		end while list.count == @per_page
		puts "#{year} #{page} pages, #{total} photos updated.         "
	end
	
	private 

	def download_list( list, &progression )
		list.each do |item|
			progression.call
			id     = item.id
			secret = item.secret
			info = flickr.photos.getInfo :photo_id => id, :secret => secret
			info['exif'] = flickr.photos.getExif :photo_id => id, :secret => secret
			download_photo info
		end
	end
	
	def get_sets
		puts "Loading sets"
		sets = {}
		page = 0
		list = nil
		begin 
			page += 1
			Retry.times(5) {
				list  = flickr.photosets.getList( :user_id => @user_id, :per_page => @per_page, :page => page )
			}
			list.each do |item|
				sets[item.title] = item.id
			end
		end while list.count == @per_page
		sets
	end

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
			@logger.error ex unless ex.message == HTTP404
			false
		end
	end

	def download_photo info
		# get destination location based on image data taken 
		from = FlickRaw.url_o(info)
		dest = get_directory(info) + "/" + image_name(info)
		meta = dest + ".json"
		# save meta info
		if !File.exists? meta
			File.open(meta,"wb") do |file|
				file.puts info.to_json
			end
		end
		# download photo/video preview
		if !File.exists? dest
			download from.gsub("https:","http:"), dest
		end
		# download video
		if info.media == "video"
			sizes = nil
			Retry.times(5) {
				sizes = flickr.photos.getSizes :photo_id => info.id
			}
			# check for video file mp4/avi/... use preview as basename
			mask = dest.gsub( "." + info.originalformat, ".???" )
			movies = Dir.glob( mask ).reject { |p| File.extname( p ) == PREVIEW_EXT }
			if movies.empty?
				original = (sizes.find {|s| s.label == 'Video Original' }).source
				dest = dest.gsub( "." + info.originalformat, MOVIE_EXT )
				dest_low = dest.gsub( MOVIE_EXT, LQ_EXT )
				if !( File.exists?( dest ) || File.exists?( dest_low ) )
					if !download(original, dest)
						site = (sizes.find {|s| s.label == 'Site MP4' }).source
						if download(site, dest_low)
							msg =  "Alternative video downloaded #{site}"
							puts msg
							@logger.info msg
						end
					end
				end
			end
		end
	end
  end


DOWNLOAD = ENV["DOWNLOAD_DIR"]
puts "FlickrDownloadr year|set"
print "Connecting ..."
config = FlickrawConfig.new
config.load_config
config.connect unless config.get_username
puts "Ok"

fd = FlickrDownloadr.new( DOWNLOAD )
ARGV.each do|a|
	i = a.to_i
	logger = Logger.new File.new("flickr-downloadr-#{a}.log", "a+")
	if i > 999 && i < 10000
		fd.download_year( i, logger ) 
	else
		fd.download_set( a, logger ) 
	end
end
