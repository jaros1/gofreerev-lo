class UsersBlankColumnApiProfileUrl < ActiveRecord::Migration

  # api_profile_url was changed to encrypted field
  def change
    User.update_all('api_profile_url = null')
  end

end
