class UsersPermissionsFbOauth22 < ActiveRecord::Migration

  # convert user.permissions attribute.
  # 1) convert OmniAuth::AuthHash to Hash
  # 2) convert old FB format {"installed"=>1, "basic_info"=>1, "public_profile"=>1, "create_note"=>1, "photo_upload"=>1, "publish_actions"=>1, "publish_checkins"=>1, "publish_stream"=>1, "publish_actions"=>1, "share_item"=>1, "video_upload"=>1, "user_friends"=>1, "bookmarked"=>1}
  #    to new FB format [{"permission"=>"public_profile", "status"=>"granted"}, {"permission"=>"read_stream", "status"=>"granted"}, {"permission"=>"publish_actions", "status"=>"granted"}, {"permission"=>"user_friends", "status"=>"granted"}]
  def change
    # 1) convert OmniAuth::AuthHash to Hash
    User.all.each do |u|
      next unless u.permissions.class == OmniAuth::AuthHash
      u.permissions = u.permissions.to_hash
      u.save!
    end
    # 2) convert old FB format {"installed"=>1, "basic_info"=>1, "public_profile"=>1, "create_note"=>1, "photo_upload"=>1, "publish_actions"=>1, "publish_checkins"=>1, "publish_stream"=>1, "publish_actions"=>1, "share_item"=>1, "video_upload"=>1, "user_friends"=>1, "bookmarked"=>1}
    #    to new FB format [{"permission"=>"public_profile", "status"=>"granted"}, {"permission"=>"read_stream", "status"=>"granted"}, {"permission"=>"publish_actions", "status"=>"granted"}, {"permission"=>"user_friends", "status"=>"granted"}]
    # that is convert permissions format used in fb oauth 1.0 to permissions format used in fb oauth 2.2
    User.all.each do |u|
      next unless u.provider == 'facebook'
      next unless u.permissions.class == Hash
      old = u.permissions
      new = []
      old.each do |name, value|
        next unless value == 1
        new << { 'permission' => name, 'status' => 'granted'}
      end
      u.permissions = new
      u.save!
    end
  end

end
