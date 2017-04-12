# FlickrDownloadr
Download personal Flickr images and store in &lt;year>/&lt;month> directory structure. This is a quick hack to get a copy of my Flickr photos.
If it crashes due to network problems, just rerun and it will try to reload remaining images (althought it first checks what has been downloaded).

Before using the script you will need a Flickr API key. Apply for a non commercial key https://www.flickr.com/services/apps/create/noncommercial/
and put them in the .env file or your environment.

This was developed using ruby 1.9.3. It is not robust and has minimal input checks. errors in settings or command line will crash the script. 
Just rerun with the correct parameters.

## Authentication
Flickr uses OAuth which is not supported by the script. the first time it finds out there is not token available and it shows an url, please use 
this in your browser to login wiht flickr. Flickr returns a token that has to be entered.
If using Windows cmd, please set the "Use legacy console" under properties otherwise it won't accep manual imput from the keyboard


## Environment settings
After getting the Flickr API key, set key and secret in your environment or the .env file. 
```
FLICKR_KEY=123af132fdsa34sdf34shufd84332
FLICKR_SECRET=dsf3247dsf83248
DOWNLOAD_DIR=c:/flickr/
BROWSER_DOWNLOAD_DIR=C:/Users/johndoe/Downloads
```

## Features
* Download all flickr photos by year or by set
* Stored in a directory per year per month

##Dependencies
- The [JSON](http://flori.github.com/json/) gem - `gem install json`.
- The [FlickRaw](https://github.com/hanklords/flickraw) gem - `gem install flickraw`
- The [DotEnv](https://github.com/bkeepers/dotenv) gem - `gem install dotenv`


## Usage
To download all files from 2017 run script with parameters.

```
c:>ruby FlickrDownloadr 2017
```

Multiple years and/or set combined:

```
c:>ruby FlickrDownloadr 2016 2017 "Family photos" SetY
```
The flickr API has some issues to download the original movie files. If the original is not available, 
the script will download a lower res version with a suffix "-low". There is a workaround to download 
originals using the a browser which has loggedin in Flickr. Use the BrowserDownload script to load these files usign the default browser. 
The script will try to download a file each 10 secs and at the end it moves all files to the correct directory.

```
c:>ruby BrowserDownload 2016 2017
```
