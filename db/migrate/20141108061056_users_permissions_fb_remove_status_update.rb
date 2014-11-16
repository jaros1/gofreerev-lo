class UsersPermissionsFbRemoveStatusUpdate < ActiveRecord::Migration

  # fb oauth 2.x - status_update has been replaced with public_actions priv.

  def change
    User.all.each do |u|
      next unless u.provider == 'facebook'
      p_array = u.permissions
      next unless p_array.class == Array
      p_status_update = p_array.find { |p| p['permission'] == 'status_update' }
      next unless p_status_update
      p_publish_actions = p_array.find { |p| p['permission'] == 'publish_actions' }
      if p_publish_actions
        # old status_update and new public_actions - remove old status_update
        p_array.delete(p_status_update)
      else
        # only old status_update - update permission name
        p_status_update['permission'] = 'publish_actions'
      end
      u.permissions = p_array
      u.save!
    end
  end
end
