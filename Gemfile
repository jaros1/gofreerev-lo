source 'https://rubygems.org'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '4.0.0'

# use omniauth for authorization / login
gem 'omniauth'

# See list of supported stategies: https://github.com/intridea/omniauth/wiki/List-of-Strategies
# login providers must have support for friends list (mutual friends, follows or followed by)
# one gem for each omniauth-xxxx gem - post login API requests - get friends, update status, send notifications etc

# find provider api reference: search for <provider> api reference endpoints rest
# find ruby gem: search for ruby <provider> gem

# 1) facebook:
# register : https://developers.facebook.com/ - select Apps in menu
# reference: https://developers.facebook.com/docs/graph-api/reference/
gem 'omniauth-facebook' # https://github.com/mkdynamic/omniauth-facebook
# gem 'koala', '1.10.0rc' # facebook API calls - https://github.com/arsduo/koala/wiki/Koala-on-Rails
# gem 'koala', '1.9.0' # facebook API calls - https://github.com/arsduo/koala/wiki/Koala-on-Rails
gem 'koala' # facebook API calls - https://github.com/arsduo/koala/wiki/Koala-on-Rails
# gem 'rest_client'
# rest-client 1.8 is using http-cookie. prefer build-in cookie-manager in http-client!
gem 'rest-client', '1.7.3' # used in FB notifications. todo: drop notifications?

# 2) flickr
# register : http://www.flickr.com/services/apps/create/
# reference: http://www.flickr.com/services/api/
gem 'omniauth-flickr' # https://github.com/timbreitkreutz/omniauth-flickr
gem 'flickraw' # flickr API calls - https://github.com/hanklords/flickraw

# 3) foursquare
# register : https://foursquare.com/developers/apps
# reference: https://developer.foursquare.com/docs/
# dependency problem between foursquare2 and linkedin: unsolved hashie dependency - foursquare2 (>= 0) depends on hashie (~> 1.0.0) - linkedin (= 1.0.0) depends on hashie (3.0.0)
gem 'omniauth-foursquare' # https://github.com/arunagw/omniauth-foursquare
gem 'foursquare2' # foursquare API calls - https://github.com/mattmueller/foursquare2

# 4) google+
# register : https://cloud.google.com/console/project - select API Project - APIs & auth - Credentials
# reference: https://developers.google.com/+/api/latest/ &
gem "omniauth-google-oauth2" # https://github.com/zquestz/omniauth-google-oauth2
gem 'google-api-client' # google+ API calls - https://github.com/google/google-api-ruby-client & https://developers.google.com/api-client-library/ruby/

# 5) instagram
# register : http://instagram.com/developer/clients/manage/#
# reference: http://instagram.com/developer/endpoints/#
gem "omniauth-instagram" # https://github.com/ropiku/omniauth-instagram
gem 'instagram' #, '0.10.0' # Instagram API calls  - https://github.com/Instagram/instagram-ruby-gem

# 6) linkedin
# register : https://www.linkedin.com/secure/developer
# reference: https://developer.linkedin.com/apis
# old oauth setup:
# gem 'omniauth-linkedin' # https://github.com/skorks/omniauth-linkedin
# gem 'linkedin', '0.4.4', :path => 'vendor/gems/linkedin-0.4.4' # LinkedIn API calls - https://rubygems.org/gems/linkedin (*)
# (*) minor change to authorize_from_request method. oauth_expires_in is saved in @auth_expires_in instance variable
# new oauth2 setup
gem 'omniauth-linkedin-oauth2' # https://github.com/decioferreira/omniauth-linkedin-oauth2
gem 'linkedin-oauth2', github: 'acvwilson/linkedin-oauth2', require: 'linkedin' # https://github.com/acvwilson/linkedin-oauth2

# 7) twitter
# register : https://apps.twitter.com/
# reference: https://dev.twitter.com/docs/api/1.1
gem 'omniauth-twitter' # https://github.com/arunagw/omniauth-twitter
gem 'twitter', '>= 5.5.1' # twitter API calls - http://sferik.github.io/twitter/
# gem 'twitter-text' # https://github.com/twitter/twitter-text-rb (truncate text & preserve tags)

# 8) VKontakte
# register : http://vk.com/dev
# reference: https://vk.com/pages?oid=-17680044&p=API_Method_Description
# (*) vkontakte 0.0.3 from RubyGems.org with a minor change in FkException
gem 'omniauth-vkontakte' # https://github.com/mamantoha/omniauth-vkontakte
gem 'httparty' # used in vkontakte
gem 'vkontakte', '0.0.3' , :path => 'vendor/gems/vkontakte-0.0.3' # http://rubygems.org/gems/vkontakte (*)

gem 'mysql2', '~> 0.3.18' # laptop and dev2 server

# Use SCSS for stylesheets
# gem 'sass-rails', '~> 4.0.0'

# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '>= 1.3.0'

# Use CoffeeScript for .js.coffee assets and views
gem 'coffee-rails', '~> 4.0.0'

# See https://github.com/sstephenson/execjs#readme for more supported runtimes
# therubyracer removed. installation error on dev3 (cubox with ubuntu 12.04)
# gem 'therubyracer', platforms: :ruby

# Use jquery as the JavaScript library
gem 'jquery-rails'

gem "jquery-ui-rails", "~> 4.0.4"

# todo: enable turbolinks and jquery-turbolinks - was outcommented in turtual http://www.jackiejohnston.us/blog/bootstrap-your-app/
# Turbolinks makes following links in your web application faster. Read more: https://github.com/rails/turbolinks
gem 'turbolinks'
# Turbolink - fix jquery document.ready - https://github.com/kossnocorp/jquery.turbolinks
gem 'jquery-turbolinks'

# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 1.2'

group :doc do
  # bundle exec rake doc:rails generates the API under doc/api.
  gem 'sdoc', require: false
end

# Use ActiveModel has_secure_password
# gem 'bcrypt-ruby', '~> 3.0.0'

# Use unicorn as the app server
# gem 'unicorn'

# Use Capistrano for deployment
group :development do
  gem "capistrano-rails"
  gem "capistrano-rvm"
end

# Use debugger
# gem 'debugger', group: [:development, :test]

# https://github.com/jmazzi/crypt_keeper
# crypt_keeper-0.13.1: problem with encrypted fields in after_insert/update callbacks. solved in 0.14.0.pre version
gem 'crypt_keeper', '~> 0.14.0.pre'

# https://github.com/bcardarella/client_side_validations
# client side validations is not ready for rails 4.0
# gem 'client_side_validations', '4-0-beta'

# https://github.com/hexorx/countries
gem 'countries'

# https://rubygems.org/gems/currencies
gem 'currencies'

# https://rubygems.org/gems/money
gem 'money'

# https://github.com/RubyMoney/google_currency
# just in case if we need to exchange currencies
# gem 'google_currency', '~> 2.3.0'
gem 'google_currency', '~> 3.0.0'

# https://github.com/svenfuchs/rails-i18n
# rails-i18n (4.0.0.pre) - example yml files for many languages
gem 'rails-i18n', '~> 4.0.0.pre'

# gem 'debugger'

group :test do
  if RUBY_PLATFORM =~ /(win32|w32)/
    gem "win32console", '1.3.0'
  end
  gem "minitest"
  gem "minitest-reporters", '>= 0.5.0'
end

gem 'open4'

gem 'fastimage'

# https://github.com/svenfuchs/routing-filter
gem 'routing-filter', '~> 0.4.0.pre'

# https://github.com/kares/session_off
gem 'session_off'

# client side translations :
# old: i18n-js-pika was a fork of i18n-js, but maybe not needed any longer ...
# https://github.com/PikachuEXE/i18n-js/tree/rails4 ()
# gem "i18n-js-pika", require: "i18n-js" # 3.0.0.rc9
# new:
# https://github.com/fnando/i18n-js
gem "i18n-js", ">= 3.0.0.rc8"

# model attribute value translation
# https://github.com/divineforest/human_attribute
gem 'human_attribute'

# https://github.com/smartinez87/exception_notification
gem 'exception_notification'


# parse open graph metatags in html pages.
# use either embedly API (free for <5000 requests per month) or opengraph (free)

# EMBEDLY = true : use embed.ly API to parse open graph metatags
# https://github.com/embedly/embedly-ruby
# http://embedly.github.io/jquery-preview/demo/
# http://embed.ly/
# used on dev2 server where there is an issue with nokogiri dependencies
# gem 'embedly'

# https://github.com/huyha85/opengraph_parser
# EMBEDLY = false: use opengraph_parser to parse open graph metatags
# used in development environment
gem "opengraph_parser"

# http://www.jackiejohnston.us/blog/bootstrap-your-app/
# broken bootstrap menu in witter-bootstrap-rails (3.2.2). ok menu in 2.2.8 (using css)
# problems with "'twitter/bootstrap/bootstrap.less' wasn't found" in 3.2.2 (using less)
gem "twitter-bootstrap-rails", '2.2.8'
# gem "twitter-bootstrap-rails", '3.2.2'
gem 'simple_form'

# angularJS - fix for ActionController::InvalidAuthenticityToken
# https://github.com/jsanders/angular_rails_csrf
gem 'angular_rails_csrf'

# fix for rake assets:precompile ExecJS::RuntimeError bootstrap.js.coffee
# http://stackoverflow.com/questions/8362458/error-when-running-rails-app-execjsruntimeerror
# gem 'therubyracer'

# server side schema json validation. https://github.com/geraintluff/tv4 is used for client side schema json validation
gem 'json-schema'

# server public private key encryption
gem 'sshkey' # https://github.com/bensie/sshkey
gem 'httpclient' # http://www.rubydoc.info/gems/httpclient/HTTPClient
# gem 'http-cookie' # https://github.com/nahi/httpclient/issues/242 (tried to fix "Unknown key: max-age = 0")
gem 'encrypted_strings' # https://github.com/pluginaweek/encrypted_strings

# dalli memory cache - store private key password information temporary in memory (1 of 5 option for password)
gem 'dalli' # https://github.com/mperham/dalli

# use when moving to an other db environment. See issue 12
# https://github.com/ludicast/yaml_db
# https://github.com/ludicast/yaml_db/pull/45
# gem 'yaml_db'

# libv8 deploy problems (libv8 -v '3.16.14.13') on CuBox-i4Pro with ubuntu 12.04
#   /usr/include/features.h:324:26: fatal error: bits/predefs.h: No such file or directory
#   compilation terminated.
#       make[1]: *** [/mnt/plugdisk/railsapps/gofreerev-lo/shared/bundle/ruby/2.0.0/gems/libv8-3.16.14.13/vendor/v8/out/arm.release/obj.target/preparser_lib/src/allocation.o] Error 1
#   make: *** [arm.release] Error 2
#   /mnt/plugdisk/railsapps/gofreerev-lo/shared/bundle/ruby/2.0.0/gems/libv8-3.16.14.13/ext/libv8/location.rb:36:in `block in verify_installation!': libv8 did not install properly, expected binary v8 archive '/mnt/plugdisk/railsapps/gofreerev-lo/shared/bundle/ruby/2.0.0/gems/libv8-3.16.14.13/vendor/v8/out/arm.release/obj.target/tools/gyp/libv8_base.a'to exist, but it was not found (Libv8::Location::Vendor::ArchiveNotFound)
#   	from /mnt/plugdisk/railsapps/gofreerev-lo/shared/bundle/ruby/2.0.0/gems/libv8-3.16.14.13/ext/libv8/location.rb:35:in `each'
#   	from /mnt/plugdisk/railsapps/gofreerev-lo/shared/bundle/ruby/2.0.0/gems/libv8-3.16.14.13/ext/libv8/location.rb:35:in `verify_installation!'
#   from /mnt/plugdisk/railsapps/gofreerev-lo/shared/bundle/ruby/2.0.0/gems/libv8-3.16.14.13/ext/libv8/location.rb:26:in `install!'
#   	from extconf.rb:7:in `<main>'
# solution can be found here:
#   https://github.com/cowboyd/libv8/tree/3.11#bring-your-own-v8
#   bundle config build.libv8 --with-system-v8
#   https://github.com/cowboyd/therubyracer/issues/215
#   gem 'libv8', '3.11.8.3'
# gem 'libv8', '3.11.8.3', :platform => :ruby
# gem 'libv8', '3.11.8.16', :platform => :ruby

gem 'passenger'