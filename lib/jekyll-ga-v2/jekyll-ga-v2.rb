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

      # Now lets check for the cache file and how old it is
      if File.exist?(cache_file_path) and ((Time.now - File.mtime(cache_file_path))/60 < refresh_rate)
        response_data = JSON.parse(File.read(cache_file_path));
      else

        #analytics = Google::APIClient.new(
        #  :application_name => ga['application_name'],
        #  :application_version => ga['application_version'])
          
        analytics = Google::Apis::AnalyticsV3::AnalyticsService.new
          
        auth = ::Google::Auth::ServiceAccountCredentials
            .make_creds(scope: 'https://www.googleapis.com/auth/analytics')
        analytics.authorization = auth

        # Load our credentials for the service account
        #key = Google::APIClient::KeyUtils.load_from_pkcs12(ga['key_file'], ga['key_secret'])
        #analytics.authorization = Signet::OAuth2::Client.new(
        #  :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
        #  :audience => 'https://accounts.google.com/o/oauth2/token',
        #  :scope => 'https://www.googleapis.com/auth/analytics.readonly',
        #  :issuer => ga['service_account_email'],
        #  :signing_key => key)

        # Request a token for our service account
        # analytics.authorization.fetch_access_token!

        params = {
          'ids' => ga['profileID'],
          'start-date' => Chronic.parse(ga['start']).strftime("%Y-%m-%d"),
          'end-date' => Chronic.parse(ga['end']).strftime("%Y-%m-%d"),
          'dimensions' => "ga:pagePath",
          'metrics' => ga['metric'],
          'max-results' => 10000
        }
          
        if ga['segment']
          params['segment'] = ga['segment']
        end
          
        if ga['filters']
          params['filters'] = ga['filters']
        end
          
        # def get_ga_data(ids, start_date, end_date, metrics, dimensions: nil, filters: nil, include_empty_rows: nil, max_results: nil, output: nil, sampling_level: nil, segment: nil, sort: nil, start_index: nil, fields: nil, quota_user: nil, user_ip: nil, options: nil, &block)

        response = analytics.get_ga_data(ga['profileID'], Chronic.parse(ga['start']).strftime("%Y-%m-%d"), Chronic.parse(ga['end']).strftime("%Y-%m-%d"), ga['metric'])
          # analytics.execute(:api_method => analytics.data.ga.get, :parameters => params)

        if response.kind_of?(Array) and response.include? "error"
            errors = reponse["error"]["errors"]
            
            errors.each { |error|
                Jekyll.logger.error "Jekyll GA:", "Client Execute Error: #{error.message}"   
            }
            
            raise RuntimeError, "Check errors from Analytics"
        end

        response_data = response

        File.open(cache_file_path, "w") do |f|
          f.write(response_data.to_json)
        end

      end

      if !response_data.nil? and response_data.include? "rows"
          results = response_data["rows"]

          endTime = Time.now - startTime

          Jekyll.logger.info "Jekyll GA:","Initializated in #{endTime} seconds"

          Jekyll.logger.info "Jekyll GA:",response_data.to_json
      end

      # site.posts.docs.each { |post|
      #   url = post.url + '/'

      #   post.data.merge!("_ga" => (results[:url]) ? results[:url].to_i : 0)
      # }
    end
  end

  class Jekyll::Post
    alias_method :original, :<=>

    # Override comparator to first try _ga value
    def <=>(other)
      if site.config['jekyll_ga']['sort'] != true
        return original(other)
      end

      if self.data['_ga'] && other.data['_ga']
        cmp = self.data['_ga'] <=> other.data['_ga']
      end
      if !cmp || 0 == cmp
        cmp = self.date <=> other.date
      elsif 0 == cmp
        cmp = self.slug <=> other.slug
      end
      return cmp
    end
  end
end
