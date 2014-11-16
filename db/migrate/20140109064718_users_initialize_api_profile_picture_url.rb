class UsersInitializeApiProfilePictureUrl < ActiveRecord::Migration
  def change
    User.where('profile_picture_url is not null').each do |u|
      u.api_profile_picture_url = u.profile_picture_url
      u.update_attribute :api_profile_picture_url,  u.api_profile_picture_url
    end
  end
end
