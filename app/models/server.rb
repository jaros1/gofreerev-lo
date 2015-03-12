class Server < ActiveRecord::Base

  # login on other gofreerev server
  # send
  def login
    site_url = self.url
    # set filename for cookie store (session cookie)
    cookie_md5_path = Digest::MD5.hexdigest(site_url).scan(/.{2}/)
    parent_dir = Rails.root.join('tmp/cookies/'+cookie_md5_path[0..-2].join('/')).to_s
    FileUtils.mkdir_p parent_dir
    cookie_store = parent_dir + '/' + cookie_md5_path.last + '.cookie'

    # start http client
    client = HTTPClient.new
    client.set_cookie_store(cookie_store)

    # get session cookie (authenticity token) from other gofreerev server
    url = URI.parse("#{site_url}en/main")
    # url = URI.parse("https://dev1.gofreerev.com/")
    puts "server: get #{url}"
    res = client.get("#{url}")
    logger.debug2 "res = #{res}"
    # client.save_cookie_store
    # client.cookie_manager.save_cookies true
    client.cookie_manager.save_all_cookies(true, true, true)

    # send login request to other gofreerev server
    s = SystemParameter.find_by_name('secret')
    secret = s.value
    s = SystemParameter.find_by_name('did')
    did = s.value
    url = URI.parse("#{site_url}util/login.json")
    request = {:client_userid => 1,
               :client_timestamp => Time.new.to_i,
               :client_secret => secret,
               :did => did,
               :pubkey => SystemParameter.public_key}
    # header = {"X-CSRF-Token" => 'lwoHFCbJovoSg%2FA94DHh5Er8SBg0vw3N0u66yubGaz0%3D' }
    # header = {"X_XSRF_TOKEN" => 'lwoHFCbJovoSg%2FA94DHh5Er8SBg0vw3N0u66yubGaz0%3D' }
    header = {"X_XSRF_TOKEN" => CGI::unescape('lwoHFCbJovoSg%2FA94DHh5Er8SBg0vw3N0u66yubGaz0%3D') }
    puts "server: post #{url}"
    res = client.post(url, :body => request, :header => header)
    logger.debug2 "res = #{res}"

  end

end
