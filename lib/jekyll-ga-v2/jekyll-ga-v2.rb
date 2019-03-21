# Adapted from https://code.google.com/p/google-api-ruby-analytics/

require 'jekyll'
require 'rubygems'
require 'googleauth'
require 'google/apis/analytics_v3'
require 'chronic'
require 'json'

module Jekyll

  class GoogleAnalytics < Generator
    priority :highest
      
    @@response_data = nil

    def generate(site)    
      unless site.config['jekyll_ga']
        return
      end
        
      Jekyll.logger.info "Jekyll GA:","Initializating"
      startTime = Time.now

      # Set "ga" to store the current config
      ga = site.config['jekyll_ga']
        
      # Local cache setup so we don't hit the sever X amount of times for same data.
      cache_directory = ga['cache_directory'] || "_jekyll_ga"
      cache_filename = ga['cache_filename'] || "ga_cache.json"
      cache_file_path = cache_directory + "/" + cache_filename

      # Set the refresh rate in minutes (how long the program will wait before writing a new file)
      refresh_rate = ga['refresh_rate'] || 60

      # If the directory doesn't exist lets make it
      if not Dir.exist?(cache_directory)
        Dir.mkdir(cache_directory)
      end

      # Now lets check for the cache file and how old it is
      if File.exist?(cache_file_path) and ((Time.now - File.mtime(cache_file_path)) / 60 < refresh_rate) and !ga["debug"]
        @@response_data = JSON.parse(File.read(cache_file_path));
      else
        analytics = Google::Apis::AnalyticsV3::AnalyticsService.new
          
         # Load our credentials for the service account (using env vars)
        auth = ::Google::Auth::ServiceAccountCredentials
            .make_creds(scope: 'https://www.googleapis.com/auth/analytics')
          
        # Assign auth
        analytics.authorization = auth
          
        # Get pages && posts from site (filtering its urls)        
        pages = site.pages.select { |page| page.name.include? ".html" }.collect { |page| filter_url(page.dir + page.name) }
        posts = site.posts.docs.collect { |doc| filter_url(doc.url.to_s) }
          
        # Concat the two arrays
        pages.push(*posts)
          
        # Create a queryString (string type) from the array
        queryString = pages.collect { |page| "ga:pagePath==#{page.to_s}" }.join(",")
        
        # Get the response
        response = get_response(analytics, ga, queryString)
          
        diff_respone = nil
        
        # Make another request to Google Analytics API to get the difference
        if ga["compare_period"]
           start_date = Chronic.parse(ga['start']).strftime("%Y-%m-%d")
           end_date = Chronic.parse(ga['end']).strftime("%Y-%m-%d")
            
           diff_date = end_date.to_date - start_date.to_date            
           diff_response = get_response(analytics, ga, queryString, start_date.to_date - diff_date.numerator.to_i, start_date) 
        end

        # If there are errors then show them
        if response.kind_of?(Array) and response.include? "error"
            errors = reponse["error"]["errors"]
            
            errors.each { |error|
                Jekyll.logger.error "Jekyll GoogleAnalytics:", "Client Execute Error: #{error.message}"   
            }
            
            raise RuntimeError, "Check errors from Google Analytics"
        end

        @@response_data = response

        # Write the response data
        File.open(cache_file_path, "w") do |f|
          f.write(@@response_data.to_json)
        end
          
        endTime = Time.now - startTime

        Jekyll.logger.info "Jekyll GoogleAnalytics:","Initializated in #{endTime} seconds"
          
        Jekyll.logger.info "Jekyll GoogleAnalytics:",@@response_data.to_json

        # Debug statments (TODO: implement a tag for this)
        # Implement a macro to use in the ga[filters] called :currentUrl (ga:pagePath=@/my/url) (from: https://stackoverflow.com/questions/46039271/google-analytics-api-get-page-views-by-url)
        # https://stackoverflow.com/questions/27936532/400-invalid-value-gapagepath-for-filters-parameter
        if @@response_data.kind_of?(Array) and @@response_data.include? "rows"
            results = @@response_data["rows"]

            if ga["debug"]
                Jekyll.logger.info "Jekyll GoogleAnalytics:", @@response_data.to_json
            end
        end
          
      end
        
    end
      
    def get_response(analytics, ga, queryString, tstart = nil, tend = nil)
       return analytics.get_ga_data(
                ga['profileID'], # ids
                tstart.nil? ? Chronic.parse(ga['start']).strftime("%Y-%m-%d") : tstart.to_s, # start_date
                tend.nil? ? Chronic.parse(ga['end']).strftime("%Y-%m-%d") : tend.to_s,   # end_date
                ga['metrics'],  # metrics
                dimensions: ga['dimensions'],
                filters: ga["filters"].to_s.empty? ? queryString : ga["filters"].to_s,
                include_empty_rows: nil,
                max_results: ga["max_results"].nil? ? 10000 : ga["max_results"].to_i, 
                output: nil, 
                sampling_level: nil, 
                segment: ga['segment']) 
    end
      
    def filter_url(url)
        if url.include? ".html"
          url = url.sub(".html", "")
        end
          
        if url.include? "index"
          url = url.sub("index", "")
        end
        
        return url
    end
      
    def get_data
       @@response_data 
    end
  end
end
