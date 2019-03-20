# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "jekyll-ga-v2/version"

Gem::Specification.new do |spec|
  spec.name          = "jekyll-ga-v2"
  spec.summary       = "Jekyll Google Analytics integration"
  spec.description   = "Google Analytics support in Jekyll blog to easily show the statistics on your website"
  spec.version       = Jekyll::Patreon::VERSION
  spec.authors       = ["z3nth10n"]
  spec.email         = ["z3nth10n@gmail.com"]
  spec.homepage      = "https://github.com/uta-org/jekyll-patreon"
  spec.licenses      = ["MIT"]
    
  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r!^(test|spec|features|assets|versions)/!) }
  spec.require_paths = ["lib"]
    
  spec.add_dependency "jekyll", "~> 3.0"
  spec.add_dependency 'googleauth', '~> 0.8.0'
  spec.add_dependency 'google-api-client', '~> 0.28.4'
  spec.add_dependency 'chronic', '~> 0.10.2'
 
  spec.add_development_dependency "rake", "~> 11.0"
  spec.add_development_dependency "rspec", "~> 3.5"
end