class Session < ActiveRecord::Base

  # create_table "sessions", force: true do |t|
  #   t.string   "session_id",              limit: 32
  #   t.integer  "last_row_id"
  #   t.float    "last_row_at"
  #   t.datetime "created_at"
  #   t.datetime "updated_at"
  #   t.text     "post_on_wall_selected"
  #   t.text     "post_on_wall_authorized"
  # end
  
  # 1) session_id
  
  # 2) last_row_id
  
  # 3) last_row_at
  
  # 4) post_on_wall_selected. Optional. Hash with true/false flag for each login provider. Encrypted text in db.
  # set from "Post?" checkbox in auth/index page
  # provider is valid login provider from /config/initializers/omniauth.rb 
  def post_on_wall_selected
    return nil unless (temp_post_on_wall_selected = read_attribute(:post_on_wall_selected))
    # logger.debug2  "temp_extended_post_on_wall_selected = #{temp_extended_post_on_wall_selected}"
    YAML::load encrypt_remove_pre_and_postfix(temp_post_on_wall_selected, 'post_on_wall_selected', 46)
  end # post_on_wall_selected
  def post_on_wall_selected=(new_post_on_wall_selected)
    if new_post_on_wall_selected
      check_type('post_on_wall_selected', new_post_on_wall_selected, 'Hash')
      write_attribute :post_on_wall_selected, encrypt_add_pre_and_postfix(new_post_on_wall_selected.to_yaml, 'post_on_wall_selected', 46)
    else
      write_attribute :post_on_wall_selected, nil
    end
  end # post_on_wall_selected=
  alias_method :post_on_wall_selected_before_type_cast, :post_on_wall_selected
  def post_on_wall_selected_was
    return post_on_wall_selected unless post_on_wall_selected_changed?
    return nil unless (temp_post_on_wall_selected = attribute_was(:post_on_wall_selected))
    YAML::load encrypt_remove_pre_and_postfix(temp_post_on_wall_selected, 'post_on_wall_selected', 46)
  end # post_on_wall_selected_was
  
  # 5) post_on_wall_authorized. Optional. Hash with true/false flag for each login provider. Encrypted text in db.
  # set when user authorizes post on api wall (internal or external link)
  # provider is valid login provider from /config/initializers/omniauth.rb 
  def post_on_wall_authorized
    return nil unless (temp_post_on_wall_authorized = read_attribute(:post_on_wall_authorized))
    # logger.debug2  "temp_extended_post_on_wall_authorized = #{temp_extended_post_on_wall_authorized}"
    YAML::load encrypt_remove_pre_and_postfix(temp_post_on_wall_authorized, 'post_on_wall_authorized', 47)
  end # post_on_wall_authorized
  def post_on_wall_authorized=(new_post_on_wall_authorized)
    if new_post_on_wall_authorized
      check_type('post_on_wall_authorized', new_post_on_wall_authorized, 'Hash')
      write_attribute :post_on_wall_authorized, encrypt_add_pre_and_postfix(new_post_on_wall_authorized.to_yaml, 'post_on_wall_authorized', 47)
    else
      write_attribute :post_on_wall_authorized, nil
    end
  end # post_on_wall_authorized=
  alias_method :post_on_wall_authorized_before_type_cast, :post_on_wall_authorized
  def post_on_wall_authorized_was
    return post_on_wall_authorized unless post_on_wall_authorized_changed?
    return nil unless (temp_post_on_wall_authorized = attribute_was(:post_on_wall_authorized))
    YAML::load encrypt_remove_pre_and_postfix(temp_post_on_wall_authorized, 'post_on_wall_authorized', 47)
  end # post_on_wall_authorized_was  
  

  ##############
  # encryption #
  ##############

  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrites non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    self.session_id
  end
  def encrypt_pk=(new_encrypt_pk_value)
    self.session_id = new_encrypt_pk_value
  end
  def new_encrypt_pk
    self.session_id
  end

end
