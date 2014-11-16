class UsersUpdateApiProfileUrl < ActiveRecord::Migration
  def change
    User.all.find_all { |u| u.api_profile_url =~ /^http:/ and %w(vkontakte linkedin instagram).index(u.provider)}.each do |u|
      u.update_attribute(:api_profile_url, u.api_profile_url.gsub(/^http:/, 'https:'))
    end
  end
end
