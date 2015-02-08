class Ping < ActiveRecord::Base

  # user_ids - Array in model - text in db - array with currently logged in oauth users
  # stored encrypted in sessions table - stored in clear in pings
  # using in util/ping to return a list with online devices/friends
  def user_ids
    return nil unless (temp_user_ids = read_attribute(:user_ids))
    # logger.debug2  "temp_user_ids = #{temp_user_ids}"
    YAML::load temp_user_ids
  end # user_ids
  def user_ids=(new_user_ids)
    if new_user_ids
      check_type('user_ids', new_user_ids, 'Array')
      write_attribute :user_ids, new_user_ids.to_yaml
    else
      write_attribute :user_ids, nil
    end
  end # user_ids=
  alias_method :user_ids_before_type_cast, :user_ids
  def user_ids_was
    return user_ids unless user_ids_changed?
    return nil unless (temp_user_ids = attribute_was(:user_ids))
    YAML::load temp_user_ids
  end # user_ids_was

  # array with internal user ids - used in ping response (online devices)
  # replicate gifts for mutual friends between online devices
  attr_accessor :mutual_friends

  # attr_accessor :internal_user_ids



end
