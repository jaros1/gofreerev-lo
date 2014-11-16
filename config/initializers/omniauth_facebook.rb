class OmniAuth::AuthHash
  def get_image_facebook
    # profile image from omniauth login is normally not used (wrong picture dimensions)
    # profile image from koala request in post login task (post_login_update_friends) is used
    # only exception is for new facebook users where profile picture from omniauth is used temporary
    image = self.info.image if self.info
    image
  end
  def get_country_facebook
    locale = self[:extra][:raw_info][:locale] if self[:extra] and self[:extra][:raw_info]
    locale = "#{locale}".last(2)
    locale = BASE_COUNTRY if locale.to_s == ""
    locale
  end
  def get_profile_url_facebook
    "#{API_URL[:facebook]}/#{self.uid}"
  end
  def get_permissions_facebook
    permissions = self.extra.raw_info.permissions.data[0] if
        self.extra and
            self.extra.raw_info and
            self.extra.raw_info.permissions and
            self.extra.raw_info.permissions.data
    permissions = permissions.to_hash if permissions.class == OmniAuth::AuthHash
    # oauth 1.0 format: {"installed"=>1, "public_profile"=>1, "create_note"=>1, "photo_upload"=>1, "publish_actions"=>1, "publish_checkins"=>1, "publish_stream"=>1, "status_update"=>1, "share_item"=>1, "video_upload"=>1}
    # oauth 2.x format: [{"permission"=>"public_profile", "status"=>"granted"}, {"permission"=>"publish_actions", "status"=>"granted"}]
    # note that declined permissions are not returned from oauth 2.x
    if permissions.class == Hash
      # remove old oauth 1.0 privs. that are not used in oauth 2.x
      permissions.delete_if { |name, value| !%w(public_profile user_friends publish_actions read_stream).index(name) }
      # convert permissions hash to an array
      permissions = permissions.collect do |name, value|
        { "permission" => name,
          "status" => case when value == 1 then 'granted' else 'declined' end }
      end
    end
    permissions
  end
end