# Adapted from https://code.google.com/p/google-api-ruby-client/

require 'jekyll'
require 'jekyll/post'
require 'rubygems'
require 'google/api_client'
require 'chronic'

module Jekyll

  class GoogleAnalytics < Generator
    safe true
    priority :highest

    def generate(site)
      if !site.config['jekyll_ga']
        return
      end

      ga = site.config['jekyll_ga']
      client = Google::APIClient.new()

      # Load our credentials for the service account
      key = Google::APIClient::KeyUtils.load_from_pkcs12(ga['key_file'], ga['key_secret'])
      client.authorization = Signet::OAuth2::Client.new(
        :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
        :audience => 'https://accounts.google.com/o/oauth2/token',
        :scope => 'https://www.googleapis.com/auth/analytics.readonly',
        :issuer => ga['service_account_email'],
        :signing_key => key)

      # Request a token for our service account
      client.authorization.fetch_access_token!
      analytics = client.discovered_api('analytics','v3')

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

      response = client.execute(:api_method => analytics.data.ga.get, :parameters => params)
      results = Hash[response.data.rows]

      site.posts.each { |post|
        url = (site.config['baseurl'] || '') + post.url + '/'
        post.data.merge!("_ga" => (results[url]) ? results[url].to_i : 0)
      }
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
