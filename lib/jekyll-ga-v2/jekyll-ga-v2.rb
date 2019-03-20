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

    def generate(site)
      Jekyll.logger.info "Jekyll GA:","Initializating"
      startTime = Time.now
        
      if !site.config['jekyll_ga']
        return
      end

      # Set "ga" to store the current config
      ga = site.config['jekyll_ga']
        
      # Local cache setup so we don't hit the sever X amount of times for same data.
      cache_directory = ga['cache_directory'] || "_jekyll_ga"
      cache_filename = ga['cache_filename'] || "ga_cache.json"
      cache_file_path = cache_directory + "/" + cache_filename
      response_data = nil

      # Set the refresh rate in minutes (how long the program will wait before writing a new file)
      refresh_rate = ga['refresh_rate'] || 60

      # If the directory doesn't exist lets make it
      if not Dir.exist?(cache_directory)
        Dir.mkdir(cache_directory)
      end
        
      Jekyll.logger.info "GA-debug: ", ga["debug"]

      # Now lets check for the cache file and how old it is
      if File.exist?(cache_file_path) and ((Time.now - File.mtime(cache_file_path)) / 60 < refresh_rate) and !ga["debug"]
        response_data = JSON.parse(File.read(cache_file_path));
      else
        analytics = Google::Apis::AnalyticsV3::AnalyticsService.new
          
         # Load our credentials for the service account (using env vars)
        auth = ::Google::Auth::ServiceAccountCredentials
            .make_creds(scope: 'https://www.googleapis.com/auth/analytics')
          
        analytics.authorization = auth
          
        # def get_ga_data(ids, start_date, end_date, metrics, dimensions: nil, filters: nil, include_empty_rows: nil, max_results: nil, output: nil, sampling_level: nil, segment: nil, sort: nil, start_index: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)

        # Get the response
        #                                                                                                                                                                              ga['filters']
        response = analytics.get_ga_data(
            ga['profileID'], # ids
            Chronic.parse(ga['start']).strftime("%Y-%m-%d"), # start_date
            Chronic.parse(ga['end']).strftime("%Y-%m-%d"),   # end_date
            ga['metric'],  # metrics
            dimensions: "ga:pagePath", # dimensions
            filters: "ga:pagePath==/", # filters
            include_empty_rows: nil,
            max_results: 10000, 
            output: nil, 
            sampling_level: nil, 
            segment: ga['segment'])

        # If there are errors then show them
        if response.kind_of?(Array) and response.include? "error"
            errors = reponse["error"]["errors"]
            
            errors.each { |error|
                Jekyll.logger.error "Jekyll GoogleAnalytics:", "Client Execute Error: #{error.message}"   
            }
            
            raise RuntimeError, "Check errors from Google Analytics"
        end

        response_data = response

        # Write the response data
        File.open(cache_file_path, "w") do |f|
          f.write(response_data.to_json)
        end
          
        Jekyll.logger.info "Jekyll GoogleAnalytics:",response_data.to_json

        # Debug statments (TODO: implement a tag for this)
        # Implement a macro to use in the ga[filters] called :currentUrl (ga:pagePath=@/my/url) (from: https://stackoverflow.com/questions/46039271/google-analytics-api-get-page-views-by-url)
        # https://stackoverflow.com/questions/27936532/400-invalid-value-gapagepath-for-filters-parameter
        if response_data.kind_of?(Array) and response_data.include? "rows"
            results = response_data["rows"]

            endTime = Time.now - startTime

            Jekyll.logger.info "Jekyll GoogleAnalytics:","Initializated in #{endTime} seconds"

            if ga["debug"]
                Jekyll.logger.info "Jekyll GoogleAnalytics:",response_data.to_json
            end
        end
          
      end
    end
  end
end
