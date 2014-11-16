class Task < ActiveRecord::Base

  # https://github.com/jmazzi/crypt_keeper - text columns are encrypted in database
  # encrypt_add_pre_and_postfix/encrypt_remove_pre_and_postfix added in setters/getters for better encryption
  # this is different encrypt for each attribute and each db row
  # _before_type_cast methods are used by form helpers and are redefined
  crypt_keeper :task_data, :encryptor => :aes, :key => ENCRYPT_KEYS[36]


  # 2) task_data - String in model - encrypted text in db - update not allowed
  # for example used for linkedin oauth client when asking for rw_nus priv (post on linkedin wall priv.)
  def task_data
    # logger.debug2  "gift.task_data: task_data = #{read_attribute(:task_data)} (#{read_attribute(:task_data).class.name})"
    return nil unless (extended_task_data = read_attribute(:task_data))
    encrypt_remove_pre_and_postfix(extended_task_data, 'task_data', 37)
  end
  def task_data=(new_task_data)
    # logger.debug2  "gift.task_data=: task_data = #{new_task_data} (#{new_task_data.class.name})"
    if new_task_data
      check_type('task_data', new_task_data, 'String')
      write_attribute :task_data, encrypt_add_pre_and_postfix(new_task_data, 'task_data', 37)
    else
      write_attribute :task_data, nil
    end
  end
  alias_method :task_data_before_type_cast, :task_data
  def task_data_was
    return task_data unless task_data_changed?
    return nil unless (extended_task_data = attribute_was(:task_data))
    encrypt_remove_pre_and_postfix(extended_task_data, 'task_data', 37)
  end # task_data_was


  # send task to ajax queue before render response
  def self.add_task (session_id, task, priority=5)
    at = Task.where('session_id = ? and task = ?', session_id, task).first
    if at
      logger.warn2 "Task #{task} is already in task queue"
      return
    end
    at = Task.new
    at.session_id = session_id
    at.task = task
    at.priority = priority
    at.save!
  end # self.add_task
  
  

  # https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
  # this extension to use different encryption for each attribute and each row
  # overwrite non model specific methods defined in /config/initializers/active_record_extensions.rb
  protected
  def encrypt_pk
    self.session_id
  end
  def encrypt_pk=(new_encrypt_pk_value)
    self.session_id = new_encrypt_pk_value
  end
  def new_encrypt_pk
    raiise "not used"
  end
  
end
