# appname - used in views and messages

# prefix for environment variables for this project
ENV_APP_NAME = 'GOFREEREV' # app name used in environment variables
ENV_RAILSENV = case Rails.env when 'development' then 'DEV' when 'test' then 'TEST' when 'production' then 'PROD' end
ENV_PREFIX = "#{ENV_APP_NAME}_#{ENV_RAILSENV}_" # GOFREEREV_DEV_

# name and url for this project
APP_NAME     = 'Gofreerev'     # app name used in views and error messages
SITE_URL     = ENV["#{ENV_PREFIX}SITE_URL"] # 'http://localhost/' # must end with /

# max number of active users (last login within the last 24 hours)
MAX_USERS     = ENV["#{ENV_PREFIX}MAX_USERS"].to_i # 100

# force ssl to protect cookie information? (true or false)
# FORCE_SSL must be true for public web server
FORCE_SSL = (Rails.env.production? or (ENV["#{ENV_PREFIX}FORCE_SSL"] == 'true'))

# where can you find source for this open source project?
CVS_NAME = 'GitHub'
CVS_URL = 'https://github.com/jaros1/gofreerev-fb'

# OS environment constants for attribute encryption (crypt_keeper + improvements)
# You can use ruby script /lib/generate_keys to generate keys and this ruby array constant
# note that ENCRYPT_KEYS[1] == ENV["GOFREEREV_DEV_KEY_2"] etc. sorry about that.
encrypt_keys = []
1.upto(60).each do |keyno|
  encrypt_keys << ENV["#{ENV_PREFIX}KEY_#{keyno}"]
end
ENCRYPT_KEYS = encrypt_keys

# negative interest calculation setup.
# Uses negative interest 5 % for positive balance. negative amounts 10 % for negative balance.
# year 1: a = 100, b = -100. year 2: a =  95, b =  -90.
# in that way we get negative interest and an increasing supply of free money between 0 and 5 % per year
NEG_INT_NEG_BALANCE_PER_YEAR = 10.0 # 10 % negative interest per year for positive balance (gifts given to others)
NEG_INT_POS_BALANCE_PER_YEAR =  5.0 # 5 % negative interest per year for negative balance (gifts received from others)
FACTOR_NEG_BALANCE_PER_YEAR = 1.0 - NEG_INT_NEG_BALANCE_PER_YEAR / 100.0 # 0.90 = 100 - 10 %
FACTOR_POS_BALANCE_PER_YEAR = 1.0 - NEG_INT_POS_BALANCE_PER_YEAR / 100.0 # 0.95 = 100 - 5 %
FACTOR_NEG_BALANCE_PER_DAY = (Math::E) ** (Math.log(FACTOR_NEG_BALANCE_PER_YEAR,Math::E) / 365) # 0.9997113827109777
FACTOR_POS_BALANCE_PER_DAY = (Math::E) ** (Math.log(FACTOR_POS_BALANCE_PER_YEAR,Math::E) / 365) # 0.9998594803001535

# user.balance is an hash with user balance for each currency. Key BALANCE_KEY is used for total balance in BASE_CURRENCY.
BASE_CURRENCY = 'USD' # store exchange rates and internal balances in this currency
BASE_COUNTRY = 'us' # default country if user country is unknown.
BASE_LANGUAGE = 'en' # default language if user language is unknown
BALANCE_KEY = 'BALANCE'
CURRENCY_LOV_LENGTH = 20 # truncate currency lov after 20 characters

DEBUG_AJAX = true # default false - set to true to get more ajax debug information - JS alerts, extra log messages etc

# max one show-more-rows ajax request every 3 seconds.
# See shared/show_more_rows and get_next_set_of_rows_error? and get_next_set_of_rows methods in application controller
# todo: minor problem with sync. of 3 seconds delay in JS and rails.
GET_MORE_ROWS_INTERVAL = 3.0

# show cookie note in top of page (EU cookie law / Directive on Privacy and Electronic Communications)
# keep time and/or text small - cookie note is intruding and irritating - nil to disable/hide cookie note
# texts are set in locale keys application.layouts.cookie_note_*
# user can accept, reject or ignore cookie note
SHOW_COOKIE_NOTE = 30 # nil or number of seconds to display cookie note in header

# user account cleanup
CLEANUP_USER_DELETED      = 6.minutes
CLEANUP_USER_DEAUTHORIZED = 14.days
CLEANUP_USER_INACTIVE     = 1.year

# offline friends suggestions. Only send friends suggestions to active users (login within the last 3 months)
# and only find friends suggestions once every 14 days
FIND_FRIENDS_LAST_LOGIN = 3.months
FIND_FRIENDS_LAST_NOTI = 2.weeks
FIND_FRIENDS_EMAIL_SENDER = ENV["#{ENV_PREFIX}en_recipients".upcase] # also used in ExceptionNotification
FIND_FRIENDS_DEV_USERIDS = ENV["#{ENV_PREFIX}en_userids".upcase].to_s.split(' ') # notification filter in dev. environment

# Use embedly API? Free for < 5000 urls per month
# https://github.com/embedly/embedly-ruby
# http://embedly.github.io/jquery-preview/demo/
# http://embed.ly/
# true: use embed.ly API. false: find opengraph gem
EMBEDLY_KEY = ENV["#{ENV_PREFIX}EMBEDLY_KEY"]
EMBEDLY = (EMBEDLY_KEY.to_s != '')
