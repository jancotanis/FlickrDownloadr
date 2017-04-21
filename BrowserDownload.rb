require 'json'
require "dotenv"
require 'fileutils'

Dotenv.load

	def image_name dir, id, title, originalformat
		dir + "/" + sanitize( title + "-" + id + "." + originalformat )
	end

	def sanitize filename 
		# satinize the name based on title
		# Split the name when finding a period which is preceded by some
		# character, and is followed by some character other than a period,
		# if there is no following period that is followed by something
		# other than a period (yeah, confusing, I know)
		fn = filename.split /(?<=.)\.(?=[^.])(?!.*\.[^.])/m

		# We now have one or two parts (depending on whether we could find
		# a suitable period). For each of these parts, replace any unwanted
		# sequence of characters with an underscore
		fn.map! { |s| s.gsub /[^a-z0-9\-]+/i, '_' } 
		# /
		# Finally, join the parts with a period and return the result
		fn.join '.'
	end

LQ_EXT = "-low.mp4"	
PREVIEW_EXT = ".jpg"
count=0
start = Time.now
processed = {}
browser = ENV["BROWSER_DOWNLOAD_DIR"]
# add title default to 
ARGV.each do|a|
	dir = File.join( ENV["DOWNLOAD_DIR"], a )
	# find all secondary sized movies
	files = Dir[ File.join( dir, '**', '*' + LQ_EXT) ].reject { |p| File.directory? p }
	puts "Dir: #{a}, #{files.count} files found"
	files.each do |file|
		print "#{file} - "
		h = {}
		# preview images are jpg
		File.open(file.gsub( LQ_EXT, PREVIEW_EXT + ".json" ),"r") do |f|
			h = JSON.parse(f.read)
		end
		mask = file.gsub( LQ_EXT, ".???" )
		movies = Dir.glob( mask ).reject { |p| File.extname( p ) == PREVIEW_EXT }
		if movies.empty?
			#photopage = h["urls"].first["_content"]
			id = h["id"]
			photopage = "https://www.flickr.com/video_download.gne?id=#{id}"
			system("start #{photopage}")
			sleep 10
			processed[id] = file
		else
			puts "Skipping #{movies.first}"
		end
	end
	puts "Moving files..."
	processed.keys.each do |key|
		original_file = processed[key]
		if original_file
			movies = Dir[ File.join(browser, '**', "#{key}.*") ].reject { |p| File.directory? p }
			movies.each do |file|
				dest = original_file.gsub!( "-low.mp4", File.extname( file ) )
				print "Move #{file} - #{dest}"
				FileUtils.mv( file, dest )
				puts ""
				processed[key] = nil
			end
		end
	end
	processed.keys.each do |key|
		original_file = processed[key]
		puts "* Didn't move #{original_file}" if original_file 
	end
end
