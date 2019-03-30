# jekyll-ga-v2 [![Build Status](https://travis-ci.org/uta-org/jekyll-ga-v2.svg?branch=master)](https://travis-ci.org/uta-org/jekyll-ga-v2) [![Gem Version](https://badge.fury.io/rb/jekyll-ga-v2.svg)](http://badge.fury.io/rb/jekyll-ga-v2)

Requires Ruby 2.5+ and Jekyll 3.8+

> A Jekyll plugin that downloads Google Analytics data and adds it to your Jekyll website. The Google Analytics metric is added to each post/page's metadata and is accessible as `page.stats`. It can be printed in a template.

## Installation

This plugin requires three Ruby gems:

```bash
$ sudo gem install chronic
$ sudo gem install google-api-client
$ sudo gem install googleauth
```

Add this line to your site's Gemfile:

```ruby
gem 'jekyll-ga-v2'
```

### Set up a service account for the Google data API

- Go to https://code.google.com/apis/console/b/0/ and create a new  project. 
- Turn on the Analytics API and accept the terms of service
- Go to `API Access` on the left sidebar menu, create a new oauth 2.0 client ID, give your project a name, and click `next`.
- Select Application type: `Service account`, and click `Create client ID`
- note the private key's password. It will probably be `notasecret` unless Google changes something. You'll need to use this value to decrypt the PCKS12 file (later explanined).
- Download the private key. Save this file because you can only download it once.
- Note the `Email address` for the Service account. You'll need this for your configuration settings and in the next step.
- Log into Google Analytics and add the service account email address as a user of your Google Analytics profile: From a report page, `Admin > select a profile > Users > New User`

#### Configuration of the environment variables

[GoogleAuth needs the following environment variables to work.](https://github.com/googleapis/google-auth-library-ruby#example-environment-variables)

There is an easy way to implement this using CircleCI (maybe you are using similar to deploy your Jekyll website). If you're not familiar with CircleCI you'll need to read carefully this post on my blog about "[How To Use Any Jekyll Plugins on GitHub Pages with CircleCI](https://z3nth10n.github.io/en/2019/03/20/jekyll-plugin-issue-with-github-pages)".

Once you implement it, you'll need to go to your [CircleCI dashboard](https://circleci.com/dashboard) search your project settings and go under "**Organization > Contexts**" and create [a new Context](https://circleci.com/docs/2.0/contexts/).

Look at my website [CircleCI.yml configuration here](https://github.com/z3nth10n/z3nth10n.github.io/blob/b9f7ef42e5fce33800aab80f8eabe6868b38f8e5/circle.yml#L54). The only thing remaining is to create the appropiate Context name, and then, create the required env vars:

![](https://i.gyazo.com/3ad97b8e09ee7e05b8496f1cd631affa.png)

**Note:** The `GOOGLE_PRIVATE_KEY` value is the output from OpenSSL. You'll need to execute the following command to get it from the `*.p12` file:

```bash
$ openssl pkcs12 -in filename.p12 -clcerts -nodes -nocerts
```

You'll need to replace all the new lines characters by `\n`. This can be easily done with Sublime Text 3 specifying the Regex options and the replacing `\n` by `\\n`.
 
## Configuration

To configure `jekyll-ga-v2`, you need to specify some information about your Google Analytics service account (as set up above) and your report settings.

Add the following block to your Jekyll site's `_config.yml` file:

```yaml
####################
# Google Analytics #
####################

jekyll_ga:
  profileID: ga:<user_id>   # Profile ID 
  start: last week          # Beginning of report
  end: now                  # End of report
  compare_period: true      
  metrics: ga:pageviews     # Metrics code
  dimensions: ga:pagePath   # Dimensions
  segment:                  # Optional
  filters:                  # Optional
  max_results: 10000        # Number of the maximum results get by the API
  debug: false              # Debug mode
```

* `profileID` is the specific report profile from which you want to pull data. Find it by going to the report page in Google Analytics. Look at the URL. It will look something like `https://www.google.com/analytics/web/?hl=en&pli=1#report/visitors-overview/###########p######/`. The number after the `p` at the end of the URL is your `profileID`.
* The `start` and `end` indicate the time range of data you want to query. They are parsed using Ruby's `Chronic` gem, so you can include relative or absolute dates, such as `now`, `yesterday`, `last month`, `2 weeks ago`. See [Chronic's documentation](https://github.com/mojombo/chronic#examples) for more options.
* The `metrics` value is what you want to measure from your Google Analytics data. Usually this will be `ga:pageviews` or `ga:visits`, but it can be any metric available in Google Analytics. Specify only one. See the [Google Analytics Query Explorer](http://ga-dev-tools.appspot.com/explorer/?csw=1) to experiment with different metrics. (Your `dimension` should always be `ga:pagePath`). I recommend you the following string `ga:pageviews,ga:bounceRate,ga:sessions,ga:users,ga:newUsers`.
* The `segment` and `filters` keys are optional parameters for your query. See the [Google Analytics Query Explorer](http://ga-dev-tools.appspot.com/explorer/?csw=1) for a description of how to use them, or just leave them out.

New params in v2:

* If `compare_period` is to true, then this will create two reports (**example:** if start is set to "last month", this will create one report from "end" to "start" and the second report its end will be at the start of the first report, with this data a comparation will be created).

### Do you need to automatize this?

Maybe you're thinking that you'll need to make a new push everytime you need to update your stats. And you're right, but CircleCI comes here again for the rescue. All you need is to [schedule a nightly build](https://circleci.com/docs/2.0/workflows/#nightly-example).

Here is my own implementation on [my CircleCI.yml configuration, again](https://github.com/z3nth10n/z3nth10n.github.io/blob/b9f7ef42e5fce33800aab80f8eabe6868b38f8e5/circle.yml#L56).

```yaml
    nightly:
        triggers:
            - schedule:
                cron: "0 0 * * *"
                filters:
                    branches:
                        only:
                            - gh-pages-ci
                        ignore:
                            - master
        jobs:
            - build:
                context: "Google Analytics Sensitive Data"
```

Of course, you'll need to specify the context again.

### Need help for examples?

Look at those two HTML files I created to render my settings:

```html
<div id="genstats" class="col-md-3 align-sm-right vertical-margin order-xs-fourth col-xs-expand">
    <box class="both-offset expand-width">
        <p>
            <h3>Statistics</h3>
            <p>(last {{ site.data.period }} days)</p>
        </p>

        {% for header in site.data.headers %}
        
            <p>
                {% assign hvalue = header.value | plus: 0 %}
                {{ hvalue | round }} {{ header.name }}
            </p>
            <p class="sub">
                    {% if site.jekyll_ga.compare_period %}
                    (
                    last {{ site.data.period }} days: 
                    {% if header.value_perc != "∞" %}
                        {% assign perc = header.value_perc | plus: 0 %}

                        {% if perc > 0 %}
                            <i class="fas fa-arrow-up color-green"></i>
                        {% elsif perc == 0 %}
                            <i class="fas fa-equals"></i>
                        {% elsif perc < 0 %}
                            <i class="fas fa-arrow-down color-red"></i>
                        {% endif %}

                        {{ perc | round }} % | 
                        
                        {% assign diff = header.diff_value %}
                        {% if diff > 0 %}+{% endif %}
                        {{ diff | round }} than last period
                    {% else %}
                    ∞ %    
                    {% endif %}
                    )
                {% endif %}
            </p>

        {% endfor %}
    </box>
</div>
```

This displays a box with the different metrics selected in your `metrics` configuration parameter:

![](https://i.gyazo.com/3105ff73fc023c5cf3506b9adcd63577.png)

I use this for any post:

```html
{% if page.stats.pageviews != blank %}
    {% assign hvalue = header.value | plus: 0 %}
    {{ hvalue | round }} views
                
    {% if site.jekyll_ga.compare_period %}
        (
        last {{ site.data.period }} days: 
        {% if page.stats.pageviews_perc != "∞" %}
            {% assign perc = page.stats.pageviews_perc | plus: 0 %}

            {% if perc > 0 %}
                <i class="fas fa-arrow-up color-green"></i>
            {% elsif perc == 0 %}
                <i class="fas fa-equals"></i>
            {% elsif perc < 0 %}
                <i class="fas fa-arrow-down color-red"></i>
            {% endif %}

            {{ perc | round }} % |
            
            {% assign diff = page.stats.diff_pageviews %}
            {% if diff > 0 %}+{% endif %}
            {{ diff | round }} than last period
        {% else %}
        ∞ %    
        {% endif %}
        )
    {% endif %}
    .
{% endif %}
```

It only displays `xx visits (percentage % | difference between two ranges)`.

## Issues

Having issues? Just report in [the issue section](/issues). **Thanks for the feedback!**

## Contribute

Fork this repository, make your changes and then issue a pull request. If you find bugs or have new ideas that you do not want to implement yourself, file a bug report.

## Donate

Become a patron, by simply clicking on this button (**very appreciated!**):

[![](https://c5.patreon.com/external/logo/become_a_patron_button.png)](https://www.patreon.com/z3nth10n)

... Or if you prefer a one-time donation:

[![](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://paypal.me/z3nth10n)

## Copyright

Copyright (c) 2019 z3nth10n (United Teamwork Association).

License: GNU General Public License v3.0