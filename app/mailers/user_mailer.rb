class UserMailer < ActionMailer::Base

  default from: FIND_FRIENDS_EMAIL_SENDER

  # sending email with friends suggestions to shared accounts where FB notifications are not possible
  def friends_suggestions (notification)

    noti_options = notification.noti_options
    email = noti_options[:email]
    login_user_ids = noti_options[:login_users].to_s.split(',')
    @login_users = User.where(:user_id => login_user_ids)
    I18n.locale = @login_users.collect { |u| u.language }.find_all { |x| x }.shuffle.first || 'en'
    friends_proposals_user_ids = noti_options[:friends_proposals].to_s.split(',')
    @friends_proposals = User.where(:user_id => friends_proposals_user_ids)
    email_id = "#{notification.noti_id}#{noti_options[:password]}"
    @link1 = "#{SITE_URL}#{I18n.locale}/about/unsubscribe?email_id=#{email_id}&choice=1"
    @link2 = "#{SITE_URL}#{I18n.locale}/about/unsubscribe?email_id=#{email_id}&choice=2"
    @link3 = "#{SITE_URL}#{I18n.locale}/auth/index"

    mail :to => email
  end # friends_suggestions


  private
  def api_profile_url (user)
    api_profile_url = user.api_profile_url_helper
    return api_profile_url if api_profile_url
    provider = user.provider
    "#{API_DOWNCASE_NAME[provider] || provider} uid #{user.uid}"
  end
  helper_method :api_profile_url



end
