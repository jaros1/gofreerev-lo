# appname - used in views and messages

# prefix for environment variables for this project
ENV_APP_NAME = 'GOFREEREV_LO' # app name used in environment variables
ENV_RAILSENV = case Rails.env when 'development' then 'DEV' when 'test' then 'TEST' when 'production' then 'PROD' end
ENV_PREFIX = "#{ENV_APP_NAME}_#{ENV_RAILSENV}_" # GOFREEREV_LO_DEV_

# name and url for this project
APP_NAME     = 'Gofreerev'     # app name used in views and error messages
SITE_URL     = ENV["#{ENV_PREFIX}SITE_URL"] # 'http://localhost/' # must start with https? and end with /

# max number of active users (last login within the last 24 hours)
MAX_USERS     = ENV["#{ENV_PREFIX}MAX_USERS"].to_i # 100

# force ssl to protect cookie information? (true or false)
# FORCE_SSL must be true for public web server
FORCE_SSL = (Rails.env.production? or (ENV["#{ENV_PREFIX}FORCE_SSL"] == 'true'))

# where can you find source for this open source project?
CVS_NAME = 'GitHub'
CVS_URL = 'https://github.com/jaros1/gofreerev-lo'

# OS environment constants for attribute encryption (crypt_keeper + improvements)
# You can use ruby script /lib/generate_keys to generate keys and this ruby array constant
# note that ENCRYPT_KEYS[1] == ENV["GOFREEREV_LO_DEV_KEY_2"] etc. sorry about that.
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

# interval between client pings. start with 3 seconds between client pings
PING_INTERVAL = 3000

# http://blog.scoutapp.com/articles/2009/07/31/understanding-load-averages
# server load average - number of cores - minus a constant 0.4
# increase ping interval if load average > MAX_AVG_LOAD
# decrease ping interval if load average < MAX_AVG_LOAD
# see util/ping
MAX_AVG_LOAD = `nproc`.to_i - 0.4 # 0.6, 1.6, 2.6, 3.6 etc

# extract country to currency hash from country gem (https://github.com/hexorx/countries) - used as default currency for new users
# country_to_currency = {} ;
# ISO3166::Country.all.each do |c1|
#   countrycode = c1[1].downcase
#   c2 = ISO3166::Country.new countrycode
#   currencycode = (c2.currency ? c2.currency.code.downcase : nil )
#   currencycode = 'gbp' if currencycode and %w(imp jep).index(currencycode)
#   country_to_currency[countrycode] = currencycode if currencycode
# end
COUNTRY_TO_CURRENCY = {"ad" => "eur", "ae" => "aed", "af" => "afn", "ag" => "xcd", "ai" => "xcd", "al" => "all",
                       "am" => "amd", "an" => "ang", "ao" => "aoa", "ar" => "ars", "as" => "usd", "at" => "eur",
                       "au" => "aud", "aw" => "awg", "az" => "azn", "ba" => "bam", "bb" => "bbd", "bd" => "bdt",
                       "be" => "eur", "bf" => "xof", "bg" => "bgn", "bh" => "bhd", "bi" => "bif", "bj" => "xof",
                       "bl" => "eur", "bm" => "bmd", "bn" => "bnd", "bo" => "bob", "bq" => "usd", "br" => "brl",
                       "bs" => "bsd", "bt" => "btn", "bv" => "nok", "bw" => "bwp", "by" => "byr", "bz" => "bzd",
                       "ca" => "cad", "cc" => "aud", "cf" => "xaf", "ch" => "chf", "ci" => "xof", "ck" => "nzd",
                       "cl" => "clp", "cm" => "xaf", "cn" => "cny", "co" => "cop", "cr" => "crc", "cu" => "cup",
                       "cv" => "cve", "cw" => "ang", "cx" => "aud", "cy" => "eur", "cz" => "czk", "de" => "eur",
                       "dj" => "djf", "dk" => "dkk", "dm" => "xcd", "do" => "dop", "dz" => "dzd", "ec" => "usd",
                       "ee" => "eur", "eg" => "egp", "eh" => "mad", "er" => "etb", "es" => "eur", "et" => "etb",
                       "fi" => "eur", "fj" => "usd", "fk" => "fkp", "fm" => "usd", "fo" => "dkk", "fr" => "eur",
                       "ga" => "xaf", "gb" => "gbp", "gd" => "xcd", "ge" => "gel", "gf" => "eur", "gg" => "gbp",
                       "gh" => "ghs", "gi" => "gip", "gl" => "dkk", "gm" => "gmd", "gn" => "gnf", "gp" => "eur",
                       "gr" => "eur", "gt" => "gtq", "gu" => "usd", "gw" => "xof", "gy" => "gyd", "hk" => "hkd",
                       "hm" => "aud", "hn" => "hnl", "hr" => "hrk", "ht" => "usd", "hu" => "huf", "id" => "idr",
                       "ie" => "eur", "il" => "ils", "im" => "gbp", "in" => "inr", "io" => "usd", "iq" => "iqd",
                       "ir" => "irr", "is" => "isk", "it" => "eur", "je" => "gbp", "jm" => "jmd", "jo" => "jod",
                       "jp" => "jpy", "ke" => "kes", "kg" => "kgs", "kh" => "khr", "ki" => "aud", "km" => "kmf",
                       "kn" => "xcd", "kp" => "kpw", "kr" => "krw", "kw" => "kwd", "ky" => "kyd", "kz" => "kzt",
                       "la" => "lak", "lb" => "lbp", "lc" => "xcd", "li" => "chf", "lk" => "lkr", "lr" => "lrd",
                       "ls" => "lsl", "lt" => "eur", "lu" => "eur", "lv" => "eur", "ly" => "lyd", "ma" => "mad",
                       "mc" => "eur", "md" => "mdl", "me" => "eur", "mf" => "eur", "mh" => "usd", "mk" => "mkd",
                       "ml" => "xof", "mm" => "mmk", "mn" => "mnt", "mp" => "usd", "mq" => "eur", "mr" => "mro",
                       "ms" => "xcd", "mt" => "eur", "mu" => "mur", "mv" => "mvr", "mw" => "mwk", "mx" => "mxn",
                       "my" => "myr", "mz" => "mzn", "na" => "nad", "nc" => "xpf", "ne" => "xof", "nf" => "aud",
                       "ng" => "ngn", "ni" => "nio", "nl" => "eur", "no" => "nok", "np" => "npr", "nr" => "aud",
                       "nz" => "nzd", "om" => "omr", "pa" => "pab", "pe" => "pen", "pf" => "xpf", "pg" => "pgk",
                       "ph" => "php", "pk" => "pkr", "pl" => "pln", "pm" => "eur", "pn" => "nzd", "pr" => "usd",
                       "pt" => "eur", "pw" => "usd", "py" => "pyg", "qa" => "qar", "re" => "eur", "ro" => "ron",
                       "rs" => "rsd", "ru" => "rub", "rw" => "rwf", "sa" => "sar", "sb" => "sbd", "sc" => "scr",
                       "sd" => "sdg", "se" => "sek", "sg" => "sgd", "sh" => "shp", "si" => "eur", "sj" => "nok",
                       "sk" => "eur", "sl" => "sll", "sm" => "eur", "sn" => "xof", "so" => "sos", "sr" => "srd",
                       "st" => "std", "sv" => "usd", "sx" => "ang", "sy" => "syp", "sz" => "szl", "tc" => "usd",
                       "td" => "xaf", "tf" => "eur", "tg" => "xof", "th" => "thb", "tj" => "tjs", "tk" => "nzd",
                       "tl" => "idr", "tn" => "tnd", "to" => "top", "tr" => "try", "tt" => "ttd", "tv" => "tvd",
                       "tw" => "twd", "tz" => "tzs", "ua" => "uah", "ug" => "ugx", "um" => "usd", "us" => "usd",
                       "uy" => "uyu", "uz" => "uzs", "va" => "eur", "vc" => "xcd", "ve" => "vef", "vg" => "usd",
                       "vi" => "usd", "vn" => "vnd", "wf" => "xpf", "ws" => "usd", "ye" => "yer", "yt" => "eur",
                       "za" => "zar", "zm" => "zmk", "zw" => "zwd"};

# check if dalli memcache is available. Used for temporary password storage in memory
raise "Please install dalli memcache: 'sudo apt-get install memcached'" unless Rails.cache.write "x", true

# server to server communication. setup private key protection. Use 1-5 of the following encryption options
# the keys offers no protection if unauthorized user has access to rails console on server
# public private key pair is regenerated if encryption password changes and old private key is lost
PK_PASS_1_ENV = ENV["#{ENV_PREFIX}PK_PASS"]
PK_PASS_2_RAILS = "rlKjLA1jgZNFQJ+z/WfNm2fID8k22y2IOi5c2mPtqlY=\n" # todo: please change string
pk_pass_3_db = nil
begin
  s = SystemParameter.find_by_name('private_key_password')
  if !s
    s = SystemParameter.new
    s.name = 'private_key_password'
    s.value = String.generate_random_string(80)
    s.save!
  end
  pk_pass_3_db = s.value
rescue ActiveRecord::StatementInvalid => e
  # ignore missing SystemParameter table doing first deploy
  puts "Ignoring ActiveRecord::StatementInvalid: #{e.message} doing first deploy"
  pk_pass_3_db = nil
end
PK_PASS_3_DB = pk_pass_3_db
text = nil
begin
  text = File.read(Rails.root.join('pk_pass.txt').to_s) # todo: please change path
rescue Errno::ENOENT
  text = nil
end
PK_PASS_4_FILE = text
Rails.cache.write('private_key_password', String.generate_random_string(80), :unless_exist => true)
PK_PASS_5_MEM = Rails.cache.fetch('private_key_password')

# check/regenerate private key
begin
  SystemParameter.private_key
rescue OpenSSL::Cipher::CipherError => e
  puts "Error. SystemParameter.private_key failed with #{e.message}. Generating new public private key pair"
  SystemParameter.generate_key_pair
  SystemParameter.private_key
rescue ActiveRecord::StatementInvalid => e
  puts "Ignoring ActiveRecord::StatementInvalid: #{e.message} doing first deploy"
  # ignore missing SystemParameter table doing first deploy
  nil
end

# server to server communication. path to signature files on other gofreerev servers.
# used when validating incoming request from gofreerev servers. see Server.signature_filename and Server.signature_url
SITE_SIGNATURE_PATH = Digest::MD5.hexdigest(SITE_URL.gsub(/^https/, 'http')).scan(/.{2}/).join('/')
