# http://stackoverflow.com/questions/13112430/find-loaded-providers-for-omniauth
# add OmniAuth::Builder.providers method to return list of loaded providers
module OmniAuth
  class Builder < ::Rack::Builder
    def provider_patch(klass, *args, &block)
      @@providers ||= []
      @@providers << klass.to_s
      old_provider(klass, *args, &block)
    end
    alias old_provider provider
    alias provider provider_patch
    class << self
      def providers
        @@providers
      end
    end
  end
end # OmniAuth

# check list for provider setup. Must be a login provider API with som kind of friend lists
# providers: https://github.com/intridea/omniauth/wiki/List-of-Strategies
#  1) add gem omniauth-<provider> (authorization ) and gem <provider> (client API operations) to GemFile.
#     that is normally two gems for each omniauth supported strategy
#     one gem for omniauth authorization and one gem for client API operations (get friends, post on wall)
#  2) get API_ID and API_SECRET for new provider. Register and add environment variables with API_ID and API_SECRET.
#     environment variable names "GOFREEREV_<env>_APP_ID_<provider>" and "GOFREEREV_<env>_APP_SECRET_<provider>"
#     for example GOFREEREV_LO_DEV_APP_ID_FACEBOOK and GOFREEREV_LO_DEV_APP_SECRET_FACEBOOK for facebook / development
#     see A) and B)
#     http://developers.gigya.com/010_Developer_Guide/82_Socialize_Setup/005_Opening_External_Applications
#  3) add provider to OmniAuth::Builder setup in this file. options are different for each provider. see C)
#  4) add provider to API_... hash constants in this file. 16 hah constants. See D) - S)
#  5) add any provider specific methods to OmniAuth::AuthHash. See config/initializers/omniauth_<provider>.rb.
#     check if auth_hash information is written correct to user record in auth/create
#  6) add init_api_client_<provider> method to application controller
#     you must as minimum supply a gofreerev_get_friends instance method to new api_client
#  7) search source code for "API SETUP" and check if new provider should be added to ruby statements

# initialize A) API_ID and B) API_SECRET hashes to be used in omni authorization and API requests
api_id     = {} # A)
api_secret = {} # B)
api_token  = {}
%w(facebook flickr foursquare google_oauth2 instagram linkedin twitter vkontakte).each do |provider|
  # get api_id for provider
  name = "#{ENV_PREFIX}app_id_#{provider}".upcase
  api_id[provider] = ENV[name]
  puts "Warning: environment variable #{name} was not found" if api_id[provider].to_s == ""
  # get api_secret for provider
  name = "#{ENV_PREFIX}app_secret_#{provider}".upcase
  api_secret[provider] = ENV[name]
  puts "Warning: environment variable #{name} was not found" if api_secret[provider].to_s == ""
  # get api_token for provider - only facebook
  if provider == 'facebook'
    # get application token:
    # api_server = Koala::Facebook::RealtimeUpdates.new :app_id => API_ID[:facebook], :secret => API_SECRET[:facebook]
    # api_server.app_access_token
    name = "#{ENV_PREFIX}app_token_#{provider}".upcase
    api_token[provider] = ENV[name]
    puts "Warning: environment variable #{name} was not found" if api_token[provider].to_s == ""
  end
end
API_ID     = api_id.with_indifferent_access     # A
API_SECRET = api_secret.with_indifferent_access # B
API_TOKEN  = api_token.with_indifferent_access

# C) - omniauth setup
Rails.application.config.middleware.use OmniAuth::Builder do
  # facebook oauth 2.2 - note that facebook friends list is almost empty in oauth 2.x - friend list only include friends that also are app users
  provider :facebook, API_ID[:facebook], API_SECRET[:facebook],
           :scope => ('public_profile,user_friends'),
           :image_size => :normal, :info_fields => "name,friends,picture,timezone",
           :client_options => {
               :site => 'https://graph.facebook.com',
               :authorize_url => "https://www.facebook.com/v2.2/dialog/oauth",
               :token_url => '/oauth/access_token'
           }
  provider :flickr, API_ID[:flickr], API_SECRET[:flickr], :scope => 'read'
  provider :foursquare, API_ID[:foursquare], API_SECRET[:foursquare]
  provider :google_oauth2, API_ID[:google_oauth2], API_SECRET[:google_oauth2], :scope => 'plus.login userinfo.profile', :access_type => 'offline', :prompt => 'consent'
  # provider :google_oauth2, :setup => GOOGLE_OAUTH2_SETUP
  provider :instagram, API_ID[:instagram], API_SECRET[:instagram]
  provider :linkedin, API_ID[:linkedin], API_SECRET[:linkedin], :scope => "r_basicprofile r_network", :fields => ['id', 'first-name', 'last-name', 'picture-url', 'public-profile-url', 'location']
  provider :twitter, API_ID[:twitter], API_SECRET[:twitter], {:image_size => 'bigger', :authorize_params => {:x_auth_access_type => 'write'}}
  provider :vkontakte, API_ID[:vkontakte], API_SECRET[:vkontakte], {:scope => 'friends,photos'}
end

# D) visit or redirect to API
API_URL = {:facebook => "https://www.facebook.com",
           :flickr => 'https://www.flickr.com/',
           :foursquare => 'https://foursquare.com',
           :google_oauth2 => "https://plus.google.com/",
           :instagram => 'http://instagram.com/', # not secure!
           :linkedin => "https://www.linkedin.com/",
           :twitter => "https://twitter.com/",
           :vkontakte => 'https://vk.com/'}.with_indifferent_access

# E) callback url used in util controller and in API specific controllers (facebook, linkedin) - request extra privs.
API_CALLBACK_URL = {:facebook => "#{SITE_URL}facebook/",
                    :flickr => "#{SITE_URL}flickr/index",
                    :foursquare => '',
                    :google_oauth2 => '',
                    :instagram => '',
                    :linkedin => "#{SITE_URL}linkedin/index",
                    :twitter => '',
                    :vkontakte => ''}.with_indifferent_access

# F) post on wall for API?
# - 0: No or readonly API
# - 1: Yes - write permission is handled within Gofreerev (internal grant write link)
# - 2: Yes - write permission is handled within API (external grant write link or log out+log in to refresh write permission)
# - 3: Yes - write permission is handled first time in API (external grant write link) and second time in Gofreerev (internal grant write link)
API_POST_NOT_ALLOWED = 0
API_POST_PERMISSION_IN_APP = 1
API_POST_PERMISSION_IN_API = 2
API_POST_PERMISSION_MIXED  = 3
API_POST_PERMITTED = {:facebook      => API_POST_PERMISSION_IN_API, # read/write handled by app
                      :flickr        => API_POST_PERMISSION_MIXED,  # first login with read permission,
                      :foursquare    => API_POST_NOT_ALLOWED,       # API with write operations but no wall
                      :google_oauth2 => API_POST_NOT_ALLOWED,       # readonly API
                      :instagram     => API_POST_NOT_ALLOWED,       # readonly API
                      :linkedin      => API_POST_PERMISSION_MIXED,  # first login with read permission, second login with write permission, internal grant write link in other sessions
                      :twitter       => API_POST_PERMISSION_IN_APP, # login with write permission
                      :vkontakte     => API_POST_PERMISSION_IN_APP  # login with write permission
                     }.with_indifferent_access

# G) API friend concept. true if API friends are mutual friends. false if API is using follows and followers
# mutual friends are also Gofreerev friends but can be deselected
# follows/followers are not Gofreerev friends but Gofreerev friend invitation is allowed
API_MUTUAL_FRIENDS = {:facebook => true,
                      :flickr => false,
                      :foursquare => true,
                      :google_oauth2 => false,
                      :instagram => false,
                      :linkedin => true,
                      :twitter => false,
                      :vkontakte => true}.with_indifferent_access

# I) link to API app settings so that user easy can review permissions
API_APP_SETTING_URL = {:facebook => 'https://www.facebook.com/settings?tab=applications',
                       :flickr => 'http://www.flickr.com/services/auth/list.gne',
                       :foursquare => 'https://foursquare.com/settings/connections',
                       :google_oauth2 => 'https://plus.google.com/apps',
                       :instagram => 'https://instagram.com/accounts/manage_access#',
                       :linkedin => 'https://www.linkedin.com/secure/settings?userAgree=&goback=.nas_*1_*1_*1',
                       :twitter => 'https://twitter.com/settings/applications',
                       :vkontakte => 'https://vk.com/settings'}.with_indifferent_access

# J) API name to be used in messages and mouse over texts
# text for "nil" API provider (not logged in or generic messages) /locales/xx.yml/shared/providers
API_DOWNCASE_NAME = {:facebook => 'facebook',
                     :flickr => 'flickr',
                     :foursquare => 'foursquare',
                     :google_oauth2 => 'google+',
                     :instagram => 'instagram',
                     :linkedin => 'linkedin',
                     :twitter => 'twitter',
                     :vkontakte => 'vkontakte'}.with_indifferent_access

# K) API name to be used in views and links
# text for "nil" API provider (not logged in or generic messages) /locales/xx.yml/shared/providers
API_CAMELIZE_NAME = {:facebook => 'Facebook',
                     :flickr => 'Flickr',
                     :foursquare => 'Foursquare',
                     :google_oauth2 => 'Google+',
                     :instagram => 'Instagram',
                     :linkedin => 'LinkedIn',
                     :twitter => 'Twitter',
                     :vkontakte => 'VKontakte'}.with_indifferent_access

# L) API profile pictures: :api or :local. Default is :api <=> Profile pictures are not downloaded from provider
# API_PROFILE_PICTURE_STORE for facebook must be :api. user.api_profile_picture_url is used in user.sha256 signature
API_PROFILE_PICTURE_STORE = {}.with_indifferent_access

# M) gift pictures: nil (no picture/readonly api), :api (use api picture url) or :local (keep local copy of picture)
# gooogle+ must be :local or nil (readonly api)
# instagram must be :local or nil (readonly api)
# linkedin must be :local or nil (only picture url is uploaded to linkedin)
# fallback must be :local or nil (use :local to enable local gift picture store as a fallback/last option)
API_GIFT_PICTURE_STORE = {:fallback => nil,
                          :facebook => :api,
                          :flickr => :api,
                          :foursquare => nil, # post possible, but no user wall like the other API's
                          :google_oauth2 => nil, # google+ is a readonly API
                          :instagram => nil, # instagram is a readonly API
                          :linkedin => :local, # images are not uploaded to LinkedIn and must be stored on gofreerev server
                          :twitter => :api,
                          :vkontakte => :api}.with_indifferent_access

# open graph values (http://ogp.me/) recommended max length for meta-tags used in deep links
# it is up to each api_client.gofreerev_post_on_wall instance method how to use max text and open graph lengths
# default values: 70 characters for title and 200 characters for description
# P) OG title meta-tag
API_OG_TITLE_SIZE = {:facebook => 94, # http://wptest.means.us.com/online-meta-tag-length-checker/
                     :flickr => 60, # Open Graph is not relevant for flickr
                     :foursquare => 60, # todo: check
                     :google_oauth2 => 63,
                     :instagram => 60, # todo: check
                     :linkedin => 60,
                     :twitter => 70,
                     :vkontakte => 60}.with_indifferent_access
# Q) OG description meta-tag
API_OG_DESC_SIZE = {:facebook => 255, # http://www.joshspeters.com/how-to-optimize-the-ogdescription-tag-for-search-and-social
                    :flickr => 155, # todo: check
                    :foursquare => 155, # todo: check
                    :google_oauth2 => 155,
                    :instagram => 155, # todo: check
                    :linkedin => 220, # max 220 in util.post_on_linkedin ( up to 245 characters allowed in og:description meta-tag )
                    :twitter => 200,
                    :vkontakte => 155}.with_indifferent_access

# R) OG dummy image - used for post without picture - see links for best image dimensions
# http://sproutsocial.com/insights/social-media-image-sizes-guide
# https://docs.google.com/spreadsheets/d/1IpTYTTMJLcSXcPDtW9zSbPBHQyRdrLfKERohGIIkE_Q/edit
API_OG_DEF_IMAGE = {:facebook => "#{SITE_URL}images/sacred-economics-facebook.jpg", # 600 x 315
                    :flickr => "#{SITE_URL}images/sacred-economics.jpg",
                    :foursquare => "#{SITE_URL}images/sacred-economics.jpg",
                    :google_oauth2 => "#{SITE_URL}images/sacred-economics-google_oauth2.jpg", # 497 x 373
                    :instagram => "#{SITE_URL}images/sacred-economics-instagram.jpg", # 510 x 510
                    :linkedin => "#{SITE_URL}images/sacred-economics-linkedin.jpg", # 180 x 110
                    :pinterest => "#{SITE_URL}images/sacred-economics.jpg",
                    :twitter => "#{SITE_URL}images/sacred-economics-twitter.jpg", # 506 x 253
                    :vkontakte => "#{SITE_URL}images/sacred-economics.jpg"}.with_indifferent_access

# S) for twitter:site card meta-tag - The Twitter username of the owner of this card's domain. - only twitter
API_OWNER = { :twitter => ENV['GOFREEREV_APP_OWNER_TWITTER'] }.with_indifferent_access


# check API hashes for missing login providers / omniauth strategies.
# action: 0: compare, 1: check first hash, 2. check second hash
def compare_keys (name1, name2, action=0)
  hash1 = eval(name1)
  hash2 = eval(name2)
  dif1 = (hash1.keys - hash2.keys).sort.join(', ')
  dif2 = (hash2.keys - hash1.keys).sort.join(', ')
  logger.warn2 "provider(s) #{dif1} missing in #{name2}" if [0,1].index(action) and !dif1.empty?
  logger.warn2 "provider(s) #{dif2} missing in #{name1}" if [0,2].index(action) and !dif2.empty?
end
compare_keys 'API_ID', 'API_SECRET'
compare_keys 'API_ID', 'API_TOKEN', 2
compare_keys 'API_ID', 'API_URL'
compare_keys 'API_ID', 'API_CALLBACK_URL'
compare_keys 'API_ID', 'API_POST_PERMITTED'
compare_keys 'API_ID', 'API_MUTUAL_FRIENDS'
compare_keys 'API_ID', 'API_APP_SETTING_URL'
compare_keys 'API_ID', 'API_DOWNCASE_NAME'
compare_keys 'API_ID', 'API_CAMELIZE_NAME'
compare_keys 'API_ID', 'API_GIFT_PICTURE_STORE', 1
compare_keys 'API_ID', 'API_OG_TITLE_SIZE'
compare_keys 'API_ID', 'API_OG_DESC_SIZE'
compare_keys 'API_ID', 'API_OG_DEF_IMAGE', 1


# extract basic information from auth_hash (provider, uid, user_name, token, language)
# provider specific versions can be implemented with get_<method>_<provider>.
# See omniauth_linkedin.rb for an example.
class OmniAuth::AuthHash
  def get_provider
    provider = self[:provider]
    provider = nil if provider.to_s == ""
    provider
  end
  def get_uid
    provider = get_provider()
    method = "get_uid_#{provider}"
    return eval(method) if respond_to? method.to_sym
    uid = self[:uid]
    uid = nil if uid.to_s == ""
    uid
  end
  def get_user_name
    provider = get_provider()
    method = "get_user_name_#{provider}"
    return eval(method) if respond_to? method.to_sym
    name = self[:info][:name] if self[:info]
    name = nil if name.to_s == ""
    nickname =self[:info][:nickname] if self[:info]
    nickname = nil if nickname.to_s == ""
    email = self[:info][:email] if self[:info]
    email = nil if email.to_s == ""
    email = email.split(/[\.|@]/).first(2).join(' ').camelcase if email
    name || nickname || email    
  end
  def get_token
    provider = get_provider()
    method = "get_token_#{provider}"
    return eval(method) if respond_to? method.to_sym
    token = self[:credentials][:token] if self[:credentials]
    token = nil if token.to_s == ""
    token
  end
  def get_expires_at
    provider = get_provider()
    method = "get_expires_at_#{provider}"
    return eval(method) if respond_to? method.to_sym
    expires_at = self[:credentials][:expires_at] if self[:credentials]
    return expires_at unless expires_at.to_s == ''
    expires = self[:credentials][:expires] if self[:credentials]
    return 1.year.from_now.to_i if expires == false
    nil
  end
  def get_refresh_token
    provider = get_provider()
    method = "get_refresh_token_#{provider}"
    return eval(method) if respond_to? method.to_sym
    nil # only implemented for google+ (access token expires in 1 hour)
  end
  def get_country
    provider = get_provider()
    method = "get_country_#{provider}"
    return eval(method) if respond_to? method.to_sym
    nil
  end
  def get_language
    provider = get_provider()
    method = "get_language_#{provider}"
    return eval(method) if respond_to? method.to_sym
    locale = self[:extra][:raw_info][:locale] if self[:extra] and self[:extra][:raw_info]
    locale = "#{locale}".first(2)
    locale = BASE_LANGUAGE if locale.to_s == ""
    locale
  end
  def get_image
    provider = get_provider()
    method = "get_image_#{provider}"
    return eval(method) if respond_to? method.to_sym
    image = self[:info][:image] if self[:info]
    image = nil if image.to_s == ""
    image = nil if image and image !~ /^https?:/
    image
  end
  def get_profile_url
    provider = get_provider()
    method = "get_profile_url_#{provider}"
    return eval(method) if respond_to? method.to_sym
    profile_url = self[:extra][:raw_info][:link] if self[:extra] and self[:extra][:raw_info]
    profile_url
  end
end # OmniAuth::AuthHash

OmniAuth.config.on_failure = AuthController.action(:oauth_failure)