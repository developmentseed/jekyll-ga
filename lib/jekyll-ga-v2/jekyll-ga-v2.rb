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
    @diff_response = nil

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
        
        # Make another request to Google Analytics API to get the difference
        if ga["compare_period"]
           start_date = Chronic.parse(ga['start']).strftime("%Y-%m-%d")
           end_date = Chronic.parse(ga['end']).strftime("%Y-%m-%d")
            
           diff_date = end_date.to_date - start_date.to_date            
           @diff_response = get_response(analytics, ga, queryString, start_date.to_date - diff_date.numerator.to_i, start_date) 
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
          
        Jekyll.logger.info "GA-debug (type): ", response.class.to_s

        # Write the response data
        File.open(cache_file_path, "w") do |f|
          f.write(@@response_data.to_json)
        end

        # Debug statments (TODO: implement a tag for this)
        # Implement a macro to use in the ga[filters] called :currentUrl (ga:pagePath=@/my/url) (from: https://stackoverflow.com/questions/46039271/google-analytics-api-get-page-views-by-url)
        # https://stackoverflow.com/questions/27936532/400-invalid-value-gapagepath-for-filters-parameter
        if @@response_data.kind_of?(Google::Apis::AnalyticsV3::GaData) and !@@response_data.rows.nil?
            results = @@response_data.rows

            # if ga["debug"]
            #    Jekyll.logger.info "Jekyll GoogleAnalytics:", @@response_data.to_json
            # end
        end
          
      end
        
      Jekyll.logger.info "Jekyll GoogleAnalytics (pre-prod):",@@response_data.to_json
        
      # Get keys from columnHeaders
      headers = @@response_data.column_headers.collect { |header| header.name.sub("ga:", "") }
      Jekyll.logger.info "GA-debug (headers): ", headers
        
      # Loop through pages && posts to add indexer value
        
      site.pages.each { |page|
          page.data["statistics"] = get_data_for("page", page, headers)
          Jekyll.logger.info "GA-debug (stats): ", page.data["statistics"]
      }
        
      site.posts.docs.each { |post|
          post.data["statistics"] = "bie"
      }
        
      endTime = Time.now - startTime

      Jekyll.logger.info "Jekyll GoogleAnalytics:", "Initializated in #{endTime} seconds"
        
    end
      
    def get_data_for(page_type, inst, headers)
       data = nil
       past_data = nil
        
       # Jekyll.logger.info "GA-debug (diff): ", @diff_response.to_json
    
       # Transpose array into hash using columnHeaders    
       if page_type == "page"
          # Jekyll.logger.info "GA-debug: ", "Parsing data from page"
           
          data = @@response_data.rows.select { |row| row[0] == filter_url(inst.dir + inst.name) }.collect { |row| Hash[ [headers, row].transpose ] }[0]
          past_data = @diff_response.nil? or !@diff_response.nil? and @diff_response.rows.nil? ? nil : @diff_response.rows.select { |row| row[0] == filter_url(inst.dir + inst.name) }.collect { |row| Hash[ [headers, row].transpose ] }[0]
       elsif page_type == "post"
          data = @@response_data.rows.select { |row| row[0] == filter_url(inst.url.to_s) }.collect { |row| Hash[ [headers, row].transpose ] }[0]
          past_data = @diff_response.nil? or !@diff_response.nil? and @diff_response.rows.nil? ? nil : @diff_response.rows.select { |row| row[0] == filter_url(inst.url.to_s) }.collect { |row| Hash[ [headers, row].transpose ] }[0]
       end
        
       if data.nil?
           # Jekyll.logger.info "GA-debug (page_type is null): ", page_type
           return nil
       end
        
       pre_data = {}    

       data.each { |key, value|
            present_value = value.to_f
           
            past_value = past_data.kind_of?(Hash) and past_data.has_key?(key) ? past_data[key].to_f : 0.0
            past_value = past_value.kind_of?(FalseClass) ? 0.0 : past_value
            # Jekyll.logger.info "GA-debug (val): ",  #prev_data.class.to_s # prev_data.nil? or !prev_data.nil? and prev_data == false
           
            if float?(value)
                diff_value = present_value - past_value
                perc_value = present_value / past_value * 100.0
                
                # Jekyll.logger.info "Growth for #{key}: ", "Present: #{present_value} | Past: #{past_value} | Diff: #{diff_value} | Perc: #{perc_value}"
                # Thanks to: https://stackoverflow.com/q/31981133/3286975
                
                pre_data.store("diff_#{key}", diff_value)
                pre_data.store("#{key}_perc", perc_value == Float::INFINITY ? "∞" : perc_value.to_s)
            end
       }
        
       data.merge!(pre_data)
        
       return data
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
      
    def float?(string)
      true if Float(string) rescue false
    end
  end
end
