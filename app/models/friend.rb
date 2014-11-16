class Friend < ActiveRecord::Base

  belongs_to :user, :class_name => 'User', :primary_key => :user_id, :foreign_key => :user_id_giver
  belongs_to :friend, :class_name => 'User', :primary_key => :user_id, :foreign_key => :user_id_receiver

  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  crypt_keeper :api_friend, :app_friend, :encryptor => :aes, :key => ENCRYPT_KEYS[15]


  ##############
  # attributes #
  ##############

  # 1) friend_id - required - not encrypted - readonly
  validates_presence_of :friend_id
  validates_uniqueness_of :friend_id
  attr_readonly :friend_id
  before_validation(on: :create) do
    self.friend_id = self.new_encrypt_pk unless self.friend_id
  end
  def friend_id=(new_friend_id)
    return self['friend_id'] if self['friend_id']
    self['friend_id'] = new_friend_id
  end

  # 2) user_id_giver - String in model and db - not encrypted
  validates_presence_of :user_id_giver
  validates_uniqueness_of :user_id_giver, :scope => :user_id_receiver

  # 3) user_id_receiver - String in model and db - not encrypted
  validates_presence_of :user_id_receiver
  validates_uniqueness_of :user_id_receiver, :scope => :user_id_giver

  # 4) api_friend. String in model. Encrypted text in db. Required
  # Y - mutual API friends
  # N - not API friends, but can be APP friends
  # F - user_id_giver follows user_id_receiver
  # S - user_id_giver is being stalked by user_id_receiver
  # P - friend proposal - inserted by /users/index?friends=find. See User.find_friends
  # F and S are being used by google+ and twitter
  validates_presence_of :api_friend
  validates_inclusion_of :api_friend, :allow_blank => true, :in => %w(Y N F S P)
  def api_friend
    # logger.debug2  "gift.api_friend: api_friend = #{read_attribute(:api_friend)} (#{read_attribute(:api_friend).class.name})"
    return nil unless (extended_api_friend = read_attribute(:api_friend))
    encrypt_remove_pre_and_postfix(extended_api_friend, 'api_friend', 16)
  end # api_friend
  def api_friend=(new_api_friend)
    # logger.debug2  "gift.api_friend=: api_friend = #{new_api_friend} (#{new_api_friend.class.name})"
    if new_api_friend
      check_type('api_friend', new_api_friend, 'String')
      write_attribute :api_friend, encrypt_add_pre_and_postfix(new_api_friend, 'api_friend', 16)
    else
      write_attribute :api_friend, nil
    end
  end # api_friend=
  alias_method :api_friend_before_type_cast, :api_friend
  def api_friend_was
    return api_friend unless api_friend_changed?
    return nil unless (extended_api_friend = attribute_was(:api_friend))
    encrypt_remove_pre_and_postfix(extended_api_friend, 'api_friend', 16)
  end # api_friend_was

  # 5) app_friend. String Y/N in model. Encrypted text in db.
  # values: nil, Y, N or R.
  #   nil (default) means that friend lists are identical in login api and in app - also used if app friendship request is ignored
  #   R - request for app friendship - used for non api friends to create connection within app
  #   Y - app friends
  #   N - not app friends
  #   B - not app friends and blocked
  def app_friend
    # logger.debug2  "gift.app_friend: app_friend = #{read_attribute(:app_friend)} (#{read_attribute(:app_friend).class.name})"
    return nil unless (extended_app_friend = read_attribute(:app_friend))
    encrypt_remove_pre_and_postfix(extended_app_friend, 'app_friend', 17)
  end # app_friend
  def app_friend=(new_app_friend)
    # logger.debug2  "gift.app_friend=: app_friend = #{new_app_friend} (#{new_app_friend.class.name})"
    if new_app_friend
      check_type('app_friend', new_app_friend, 'String')
      raise TypeError, "Allowed values for app_friend is Y, N, R, P and B" unless %w(Y N R P B).index(new_app_friend)
      write_attribute :app_friend, encrypt_add_pre_and_postfix(new_app_friend, 'app_friend', 17)
    else
      write_attribute :app_friend, nil
    end
  end # app_friend=
  alias_method :app_friend_before_type_cast, :app_friend
  def app_friend_was
    return app_friend unless app_friend_changed?
    return nil unless (extended_app_friend = attribute_was(:app_friend))
    encrypt_remove_pre_and_postfix(extended_app_friend, 'app_friend', 17)
  end # app_friend_was

  # cache friend when sortering users - used in sort_by_user_name
  # sort on dev1 server took 5 seconds for a relative little sort with 74 users without cache
  attr_accessor :cache_friend_id
  attr_accessor :cache_friend_user_name


  ##################
  # helper methods #
  ##################

  #def self.add_friend(userid1, userid2, api_friend)
  #  logger.debug2 "userid1 = #{userid1}, userid2 = #{userid2}, api_friend"
  #  transaction do
  #    # check for any old information about blocked or deselect app friend
  #    # ( information is kept even if user delete and recreates account )
  #    f2 = Friend.where('user_id_giver = ? and user_id_receiver = ?', userid2, userid1).first
  #    f1 = Friend.new
  #    f1.user_id_giver = userid1
  #    f1.user_id_receiver = userid2
  #    f1.api_friend = api_friend
  #    if f2
  #      f1.app_friend = case f2.app_friend
  #                        when 'B' then 'N' # other user has blocked user1 = login user
  #                        when 'N' then 'N' # other user has deselect user1 = login user
  #                        else nil
  #                      end
  #    else
  #      f1.app_friend = nil
  #    end
  #    f1.save!
  #    f2 = Friend.new unless f2
  #    f2.user_id_giver = userid2
  #    f2.user_id_receiver = userid1
  #    f2.api_friend = 'N' unless f2.api_friend = 'N'
  #    if api_friend = 'F'
  #      # S + F = Y
  #      f2.api_friend = case f2.api_friend
  #                        when 'N'
  #                          'F'
  #                        when 'S'
  #                          'Y'
  #                        else
  #                          api_friend
  #                      end # case
  #    else
  #      f2.api_friend = api_friend
  #    end
  #    f2.save!
  #  end # transaction
  #end # self.add_friend
  #
  #def self.update_friend(login_user_id, friend_user_id, f1, f2, api_friend)
  #  if !f1
  #    # create missing friend (error)
  #    f1 = Friend.new
  #    f1.user_id_giver = login_user_id
  #    f1.user_id_receiver = friend_user_id
  #    f1.app_friend = nil
  #  end
  #  if !f2
  #    # create missing friend (error)
  #    f2 = Friend.new
  #    f2.user_id_giver = friend_user_id
  #    f2.user_id_receiver = login_user_id
  #    f2.app_friend = nil
  #  end
  #  f1.api_friend = api_friend
  #  f2 = case api_friend
  #         when 'Y' then 'Y'
  #         when 'F' then 'S'
  #         when
  #       end
  #
  #
  #  # logger.debug2  "before save"
  #  # logger.debug2  "update f1: giver = #{f1.user_id_giver}, receiver = #{f1.user_id_receiver}, api = #{f1.api_friend}, app = #{f1.app_friend}"
  #  # logger.debug2  "update f2: giver = #{f2.user_id_giver}, receiver = #{f2.user_id_receiver}, api = #{f2.api_friend}, app = #{f2.app_friend}"
  #  f1.save!
  #  f2.save!
  #end
  #
  #def self.remove_friend(userid1, userid2)
  #  transaction do
  #    f1 = Friend.where("user_id_giver = ? and user_id_receiver = ?", userid1, userid2).first
  #    f2 = Friend.where("user_id_giver = ? and user_id_receiver = ?", userid2, userid1).first
  #    if !f1.app_friend and !f2.app_friend
  #      # default app_friend value (nil)
  #      f1.destroy! if f1
  #      f2.destroy! if f2
  #      return
  #    end
  #    # non default app_friend value (N, B)
  #    f1.api_friend = 'N'
  #    f2.api_friend = 'N'
  #    f1.save!
  #    f2.save!
  #  end # transaction
  #end # self.remove_friend

  def api_friend?
    api_friend == 'Y'
  end
  def app_friend?
    app_friend == 'Y'
  end


  # google+ and twitter. api friend = Y is only used for mutual friends
  # use F (follower) if login user is following then other user
  # use S (stakler) if other user if following login user
  # api friend: Y = F + S
  private
  def self.remove_follow (api_friend)
    case api_friend
      when 'Y'
        # change friend api status from mutual friend to a stalker
        'S'
      when 'F'
        # change friend api status from follow to not a friend
        'N'
      else
        api_friend
    end # case
  end # remove_as_follower
  private
  def self.add_follow (api_friend)
    case api_friend
      when 'N'
        # follow friend
        'F'
      when 'S'
        # change friend status from a stalker to a mutual friend
        'Y'
      else
        api_friend
    end # case
  end # add_as_follower

  # update friends table with hash of friends received from login provider (api_client.gofreerev_get_friends)
  # options: login_user_id and friends_hash
  # - login_user_id: "#{uid}/#{provider}"
  # - friends_hash: = { userid1 => {:name=> username1,
  #                                 :api_profile_url=> api_profile_url1,
  #                                 :api_profile_picture_url => api_profile_picture_url1,
  #                                 :no_api_friends=> no_api_friends1},
  #                     userid2 => { ...}
  #                     ...
  #                     useridn => { ...}
  #                   }
  # not all fields are available for all login providers
  # do not include field in hash if field should not be updated
  # include field in hash if field should be updated (nil is allowed)
  def self.update_api_friends_from_hash (options)
    new_user = nil
    # get params
    login_user_id = options[:login_user_id]
    new_friends = options[:friends_hash]
    # logger.debug2 "friends_hash = #{new_friends}"

    # get provider - friends concept - mutual friends in facebook and linkedin - followers/stalkers in google+, instagram and twitter
    provider = login_user_id.split('/').last

    # check fields in friends_hash
    allowed_fields = [:name, :api_profile_url, :api_profile_picture_url, :no_api_friends, :api_friend]
    required_fields = [:name]
    new_friends.each do |user_id, hash|
      fields = hash.keys
      missing_required_fields = required_fields - fields
      if missing_required_fields.size > 0
        return [new_user,
                '.post_login_fl_missing_field',
                { :provider => provider, :apiname => (API_DOWNCASE_NAME[:provider] || provider),
                  :userid => login_user_id, :field => missing_required_fields.first } ]
      end
      invalid_fields = fields - allowed_fields
      if invalid_fields.size > 0
        return [new_user,
                '.post_login_fl_invalid_field',
                { :provider => provider, :apiname => (API_DOWNCASE_NAME[:provider] || provider),
                  :userid => login_user_id, :field => invalid_fields.first } ]
      end
    end
    fields = [] ; new_friends.each { |key, hash| fields = (fields + hash.keys).uniq }
    logger.debug2 "fields = #{fields.join(', ')}"

    mutual_friends = API_MUTUAL_FRIENDS[provider] # true for facebook and linkedin, false for google+, instagram and twitter
    if fields.index(:api_profile_picture_url)
      # check picture store for profile pictures
      picture_store = API_PROFILE_PICTURE_STORE[provider] || :api
      if ![:local,:api].index(picture_store)
        logger.fatal2 "unknown profile picture store #{picture_store} for login provider #{provider}"
        logger.fatal2 "please check array constant API_PROFILE_PICTURE_STORE (/config/initializers/omniauth.rb"
        picture_store = :api
      end
    end
    # get old friends list
    old_friends         = {} # f1 - friends and follows
    reverse_old_friends = {} # f2 - friends and stalkers
    Friend.where('(user_id_giver = ? or user_id_receiver = ?) and user_id_giver <> user_id_receiver',
                 login_user_id, login_user_id).includes(:friend).each do |f|
      if f.user_id_giver == login_user_id
        old_friends[f.user_id_receiver] = f
      else
        reverse_old_friends[f.user_id_giver] = f
      end
    end

    new_user_ids = new_friends.keys - old_friends.keys
    logger.debug2 "new_friends.keys = #{new_friends.keys.join(', ')}"
    logger.debug2 "old_friends.keys = #{old_friends.keys.join(', ')}"
    logger.debug2 "new_user_ids     = #{new_user_ids.join(', ')}"
    # check new users in friends list
    new_users = {}
    if new_user_ids.size > 0
      User.where('user_id in (?)', new_user_ids).each do |user|
        new_users[user.user_id] = user
      end
    end
    # create new users with minimal information - not all fields are available for all login providers
    (new_user_ids - new_users.keys).each do |user_id|
      user = User.new
      user.user_id = user_id
      user.user_name               = new_friends[user_id][:name]
      user.api_profile_url         = new_friends[user_id][:api_profile_url]
      user.api_profile_picture_url = new_friends[user_id][:api_profile_picture_url]
      user.no_api_friends          = new_friends[user_id][:no_api_friends]
      user.post_on_wall_yn         = 'N'
      user.save!
      new_users[user_id] = user
    end

    # loop for all old and new friends
    (old_friends.keys + new_friends.keys).each do |user_id|
      # find old and new api friend status
      if old_friends.has_key?(user_id)
        old_api_friend = old_friends[user_id].api_friend || 'N'
      else
        old_api_friend = 'N'
      end
      if new_friends.has_key?(user_id)
        if mutual_friends
          # facebook and linkedin - mutual friends
          new_api_friend = 'Y'
        elsif %w(Y S F).index(new_friends[user_id][:api_friend])
          # instagram - follows and followed_by friends list received from API
          new_api_friend = new_friends[user_id][:api_friend]
        else
          # google+ and twitter - only follows friend list received from API
          new_api_friend = Friend.add_follow(old_api_friend)
        end
      else
        if old_api_friend == 'P'
          # keep friends proposals after login
          new_api_friend = 'P'
        elsif mutual_friends
          new_api_friend = 'N'
        elsif provider == 'instagram'
          new_api_friend = 'N'
        else
          new_api_friend = Friend.remove_follow(old_api_friend)
        end
      end
      # how does api friendship looks like from the other side?
      if mutual_friends
        new_reverse_api_friend = new_api_friend
      else
        new_reverse_api_friend = case new_api_friend
                                   when 'S'
                                     # login user is stalked by friend. Friend is following login user
                                     'F'
                                   when 'F'
                                     # login user is following friend. Friend is stalked by login user
                                     'S'
                                   else
                                     new_api_friend
                                 end # case
      end

      # update friend user information (:name, :api_profile_url, :api_profile_picture_url, :no_api_friends)
      if %w(Y F).index(new_api_friend)
        # logger.debug2 "new_users   = #{new_users.keys.join(', ')}"
        # logger.debug2 "old_friends = #{old_friends.keys.join(', ')}"
        # logger.debug2 "user_id     = #{user_id}"
        friend_user = new_users[user_id] || old_friends[user_id].friend
        hash = new_friends[user_id]
        if hash.has_key?(:name)
          # update name
          if friend_user.user_name != hash[:name]
            friend_user.user_name = hash[:name].force_encoding('UTF-8')
          end
        end
        if hash.has_key?(:api_profile_url)
          # update api_profile_url
          if friend_user.api_profile_url != hash[:api_profile_url]
            friend_user.api_profile_url = hash[:api_profile_url]
          end
        end
        if hash.has_key?(:api_profile_picture_url)
          # update api_profile_picture_url
          if friend_user.api_profile_picture_url != hash[:api_profile_picture_url]
            # check picture store
            # do not overwrite old picture if local picture store and old picture url is an local url
            local = (picture_store == :local and Picture.app_url?(hash[:api_profile_picture_url]))
            if !hash[:api_profile_picture_url] or picture_store == :api or !local
              friend_user.api_profile_picture_url = hash[:api_profile_picture_url]
            end
          end
        end
        if hash.has_key?(:no_api_friends)
          # update no_api_friends
          if friend_user.no_api_friends != hash[:no_api_friends]
            # logger.debug2  "fetch_user: update api profile url: old url = #{hash[:old_no_api_friends]}, new url = #{hash[:new_no_api_friends]}"
            friend_user.no_api_friends = hash[:no_api_friends]
          end
        end
        friend_user.save! if friend_user.changed?
      end

      # update api friend status
      f1 = old_friends[user_id]
      if !f1
        f1 = Friend.new
        f1.user_id_giver = login_user_id
        f1.user_id_receiver = user_id
      end
      f2 = reverse_old_friends[user_id]
      if !f2
        f2 = Friend.new
        f2.user_id_giver = user_id
        f2.user_id_receiver = login_user_id
      end
      f1.api_friend = new_api_friend
      f2.api_friend = new_reverse_api_friend
      if f1.new_record? or f1.changed? or f2.new_record? or f2.changed?
        transaction do
          f1.save! if f1.new_record? or f1.changed?
          f2.save! if f2.new_record? or f2.changed?
        end # transaction
      end # if

      # todo: check of f1 and f2 can be deleted
    end # each user_id

    # todo: delete removed friends that is not used by any other users

    # new gofreerev user? special post_login_<provider> ok message for new users.
    new_user = ((old_friends.size == 0) and (new_friends.size > 0))
    logger.debug2 "old_friends.size = #{old_friends.size}, new_friends.size = #{new_friends.size}, new_user = #{new_user}"
    [new_user, nil, nil]
  end # self.update_friends_from_hash

  public
  def friend_status_code
    app_friend = self.app_friend
    app_friend = nil if app_friend == 'R' # R (friend request) not used in friends_hash
    app_friend = nil if app_friend == 'P' # P (pending friend request) not used in friends_hash
    app_friend || api_friend
  end # friend_status_code


  ##############
  # encryption #
  ##############

  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrites non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    self.friend_id
  end
  def encrypt_pk=(new_encrypt_pk_value)
    self.friend_id = new_encrypt_pk_value
  end
  def new_encrypt_pk
    loop do
      temp_friend_id = String.generate_random_string(20)
      return temp_friend_id unless Friend.find_by_friend_id(temp_friend_id)
    end
  end


end
