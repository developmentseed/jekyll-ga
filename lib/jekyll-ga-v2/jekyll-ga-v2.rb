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
      
    @response_data = nil
    @past_response = nil
    @headers = nil

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

      # Set the refresh rate in minutes (how long the program will wait in minutes before writing a new file)
      refresh_rate = ga['refresh_rate'] || 60

      # If the directory doesn't exist lets make it
      if not Dir.exist?(cache_directory)
        Dir.mkdir(cache_directory)
      end

      # Now lets check for the cache file and how old it is (if it exceeds refesh_rate then update it)
      if File.exist?(cache_file_path) and ((Time.now - File.mtime(cache_file_path)) / 60 < refresh_rate) and !ga["debug"]
        # Inject from cache  
        data = JSON.parse(File.read(cache_file_path))  
          
        # Into pages...
        site.pages.each { |page|
            page.data["stats"] = data["page-stats"][get_identifier_for("page", page)]
        }  
          
        # Into posts...
        site.posts.docs.each { |post|
            post.data["stats"] = data["post-stats"][get_identifier_for("post", post)]
        } 
          
        # Into site...
        site.data["stats"] = data["site-stats"] 
        site.data["period"] = data["period"]
        site.data["headers"] = data["headers"]
      else
        analytics = Google::Apis::AnalyticsV3::AnalyticsService.new
        # Google::Apis::AnalyticsreportingV4::AnalyticsReportingService.new

        # scopes = ['https://www.googleapis.com/auth/analytics.readonly']
          
        # Load our credentials for the service account (using env vars)
        # auth = Google::Auth.get_application_default(scopes)
        auth = ::Google::Auth::ServiceAccountCredentials
                  .make_creds(scope: 'https://www.googleapis.com/auth/analytics')

        # ::Google::Auth::ServiceAccountCredentials
        #     .make_creds(
        #       # scope: 'secret/client_secret.json'
        #       json_key_io: File.open(File.join(__dir__, "client_secret.json"))
        #     )
            # .make_creds(scope: 'https://www.googleapis.com/auth/analytics')
          
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

        # Jekyll.logger.info "xxx: ", response.to_json
        # Jekyll.logger.info "xxx rows: ", response.to_json


        # Jekyll.logger.info "xxx: ", response
          
        # Declare the hash where the info will go  
        store_data = {}
        
        # Make another request to Google Analytics API to get the pasterence
        if ga["compare_period"]
           start_date = Chronic.parse(ga['start']).to_date
           end_date = Chronic.parse(ga['end']).to_date

           startdateStr = start_date.strftime("%Y-%m-%d")
           enddateStr = end_date.strftime("%Y-%m-%d")

           if start_date > DateTime.now or end_date > DateTime.now
              raiseError("Start or end date can't be on the future! Start date: " + startdateStr + "; End date: " + enddateStr) 
           end
            
           if start_date > end_date
              raiseError("Start can't be a posterior date to end! Start date: " + startdateStr + "; End date: " + enddateStr) 
           end
            
           diff_date = end_date - start_date
           diff_date = diff_date.numerator.to_i
            
           site.data["period"] = diff_date
           store_data.store("period", diff_date)
          
           responseDiffDate = (start_date - diff_date).strftime("%Y-%m-%d")
           @past_response = get_response(analytics, ga, queryString, responseDiffDate, startdateStr) 
        end

        # If there are errors then show them
        if response.kind_of?(Array) and response.include? "error"
            errors = reponse["error"]["errors"]
            
            errors.each { |error|
                Jekyll.logger.error "Jekyll GoogleAnalytics:", "Client Execute Error: #{error.message}"   
            }
            
            raise RuntimeError, "Check errors from Google Analytics"
        end

        @response_data = response
          
        # Get keys from columnHeaders
        @headers = @response_data.column_headers.collect { |header| header.name.sub("ga:", "") }

        # Loop through pages && posts to add the stats object value
        page_data = {}
        site.pages.each { |page|
            stats_data = get_stats_for(ga, "page", page)
            page.data["stats"] = stats_data
            
            # Jekyll.logger.info "GA-debug (stats-type): ", page.data["statistics"].class.to_s

            unless stats_data.nil?
              page_data.store(get_identifier_for("page", page), stats_data)
                
              if ga["debug"]
                Jekyll.logger.info "GA-debug (page-stats): ", page.data["stats"].to_json
              end
            end
        }
        store_data.store("page-stats", page_data)

        post_data = {}
        site.posts.docs.each { |post|
            stats_data = get_stats_for(ga, "post", post)
            post.data["stats"] = stats_data

            unless stats_data.nil?
              post_data.store(get_identifier_for("post", post), stats_data)
                
              if ga["debug"]
                Jekyll.logger.info "GA-debug (post-stats): ", post.data["stats"].to_json
              end
            end
        }
        store_data.store("post-stats", post_data)

        # Do the same for the site
        stats_data = get_stats_for(ga, "site")
        site.data["stats"] = stats_data
          
        store_data.store("site-stats", stats_data)

        if !stats_data.nil? and ga["debug"]
          Jekyll.logger.info "GA-debug (site-stats): ", site.data["stats"].to_json
        end

        # TODO: Return 0
        if stats_data.nil?
            return nil
        end
        
        # Before saving modify headers
        
        # Create a new array with the value, the diff and the perc from the last stored stats_data corresponding to the site one
        new_headers = []
        @headers.each { |header|
            unless stats_data[header].nil?            
                protoheader = {}

                protoheader.store("name", header)
                protoheader.store("value", stats_data[header])
                protoheader.store("diff_value", stats_data["diff_#{header}"])
                protoheader.store("value_perc", stats_data["#{header}_perc"])

                new_headers.push(protoheader)
            end
        }
          
        # Then save...  
        site.data["headers"] = new_headers
        store_data.store("headers", new_headers)

        # Write the response data
        if File.exist?(cache_file_path) and ((Time.now - File.mtime(cache_file_path)) / 60 >= refresh_rate) and ga["debug"] or !ga["debug"] or !File.exist?(cache_file_path)
            File.open(cache_file_path, "w") do |f|
              f.write(JSON.pretty_generate(store_data))
            end
        end
      end
        
      endTime = Time.now - startTime

      Jekyll.logger.info "Jekyll GoogleAnalytics:", "Initializated in #{endTime} seconds"
    end
      
    def get_identifier_for(page_type, inst)
        if page_type == "page"
            return filter_url(inst.dir + inst.name)
        elsif page_type == "post"
            return filter_url(inst.url.to_s)
        end
    end
      
    def get_stats_for(ga, page_type, inst = nil)
       data = nil
       past_data = nil
        
       if @response_data.rows.nil?
          return nil
       end

       # Transpose array into hash using columnHeaders    
       if page_type == "page"
          data = @response_data.rows.select { |row| row[0] == filter_url(inst.dir + inst.name) }.collect { |row| Hash[ [@headers, row].transpose ] }[0]
          past_data = @past_response.nil? or !@past_response.nil? and @past_response.rows.nil? ? nil : @past_response.rows.select { |row| row[0] == filter_url(inst.dir + inst.name) }.collect { |row| Hash[ [@headers, row].transpose ] }[0]
       elsif page_type == "post"
          data = @response_data.rows.select { |row| row[0] == filter_url(inst.url.to_s) }.collect { |row| Hash[ [@headers, row].transpose ] }[0]
          past_data = @past_response.nil? or !@past_response.nil? and @past_response.rows.nil? ? nil : @past_response.rows.select { |row| row[0] == filter_url(inst.url.to_s) }.collect { |row| Hash[ [@headers, row].transpose ] }[0]
       elsif page_type == "site"
          data = get_site_data(false)
          past_data = get_site_data(true)
       end
        
       if data.nil?
           return nil
       end
        
       # Create diff_xxx and xxx_perc keys for data    
       if ga["compare_period"]
           pre_data = {}
           
           data.each { |key, value|
                present_value = value.to_f

                past_value = nil

                if past_data.kind_of?(Hash)
                   past_value = past_data.fetch(key, 0.0).to_f
                else
                   past_value = 0.0 
                end

                if float?(value) and float?(past_value) # Filter for pagePath (not float or integer value)
                    # Thanks to: https://stackoverflow.com/q/31981133/3286975
                    diff_value = present_value - past_value
                    perc_value = present_value / past_value * 100.0

                    pre_data.store("diff_#{key}", diff_value)
                    pre_data.store("#{key}_perc", perc_value == Float::INFINITY ? "∞" : (perc_value.nan? ? "0" : perc_value.to_s))
                end
           }

           data.merge!(pre_data)
       end
        
       return data
    end
      
    def get_site_data(is_past)
        data = (is_past ? @past_response : @response_data).totals_for_all_results
        data.keys.each { |k| data[k.sub("ga:", "")] = data[k]; data.delete(k) }
        
        return data;
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
      
    def float?(string)
      true if Float(string) rescue false
    end
      
    def raiseError(str)
        raise RuntimeError, str
    end
  end
end