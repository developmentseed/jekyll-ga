# jekyll-ga

A Jekyll plugin that downloads Google Analytics data and adds it to posts. The Google Analytics metric is added to each post's metadata and is accessible as `post._ga`. It can be printed in a template, or optionally, posts can be sorted based on the metric instead of the default reverse chronological order. This is useful for making a site that lists "most popular" content.

## Installation

This plugin requires two Ruby gems:

```bash
$ sudo gem install chronic
$ sudo gem install google-api-client
```

Copy `jekyll-ga.rb` to a `/_plugins/` directory in the root of your Jekyll site repository.

The `jekyll-ga` plugin is only tested to work with Jekyll 0.11.2 and Ruby 1.8.7, but it may work with other versions.

### Set up a service account for the Google data API

- Go to https://code.google.com/apis/console/b/0/ and create a new  project. 
- Turn on the Analytics API and accept the terms of service
- Go to `API Access` on the left sidebar menu, create a new oauth 2.0 client ID, give your project a name, and click `next`.
- Select Application type: `Service account`, and click `Create client ID`
- note the private key's password. It will probably be `notasecret` unless Google changes something. You'll need to enter this value in your configuration settings.
- Download the private key. Save this file because you can only download it once. Copy it to the root of your Jekyll repository. **Safety tip: To protect this file, add its file name to your [.gitignore](https://help.github.com/articles/ignoring-files) file and to the [exclude](https://github.com/mojombo/jekyll/wiki/Configuration#configuration-settings) list in your `_config.yml` file**
- Note the `Email address` for the Service account. You'll need this for your configuration settings and in the next step.
- Log into Google Analytics and add the service account email address as a user of your Google Analytics profile: From a report page, `Admin > select a profile > Users > New User`
 
## Configuration

To configure `jekyll-ga`, you need to specify some information about your Google Analytics service account (as set up above) and your report settings.

Add the following block to your Jekyll site's `_config.yml` file:

```yml
jekyll_ga:
  service_account_email:    # service account email address
  key_file: privatekey.p12  # service account private key file
  key_secret: notasecret    # service account private key's password
  profileID: ga:####        # profile ID 
  start: last month         # Beginning of report
  end: now                  # End of report
  metric: ga:pageviews      # Metric code
  segment:                  # optional
  filters:                  # optional
  sort: true                # Sort posts by this metric
```

`service_account_email`, `key_file`, and `key_secret` come from the Google API console when you set up your service account.

`profileID` is the specific report profile from which you want to pull data. Find it by going to the report page in Google Analytics. Look at the URL. It will look something like `https://www.google.com/analytics/web/?hl=en&pli=1#report/visitors-overview/###########p######/`. The number after the `p` at the end of the URL is your `profileID`.

The `start` and `end` indicate the time range of data you want to query. They are parsed using Ruby's `Chronic` gem, so you can include relative or absolute dates, such as `now`, `yesterday`, `last month`, `2 weeks ago`. See [Chronic's documentation](https://github.com/mojombo/chronic#examples) for more options.

The `metric` value is what you want to measure from your Google Analytics data. Usually this will be `ga:pageviews` or `ga:visits`, but it can be any metric available in Google Analytics. Specify only one. See the [Google Analytics Query Explorer](http://ga-dev-tools.appspot.com/explorer/?csw=1) to experiment with different metrics. (Your `dimension` should always be `ga:pagePath`)

The `segment` and `filters` keys are optional parameters for your query. See the [Google Analytics Query Explorer](http://ga-dev-tools.appspot.com/explorer/?csw=1) for a description of how to use them, or just leave them out.

The `sort` key can be `true` or `false`. If `true`, your posts will be sorted first by your Google Analytics metic, then chronologically as is the default. If `false` or not specified, your posts will sort as usual.

## Advanced sorting

This plugin compliments [Jekyll-Sort](https://github.com/krazykylep/Jekyll-Sort), so you can use your Google Analytics metric with a Jekyll-Sort rule by adding the following to `_config.yml`:

```yml
jekyll_ga:
  sort: false
jekyll_sort:
  - src: posts
    by: _ga
    direction: down
    dest: posts_popular
```

This allows you to have your site sorted normally (by reverse chronology) and also have a special `site.posts_popular` list of posts sorted by the specificed Google Analytics metric.
