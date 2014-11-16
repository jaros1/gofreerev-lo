# https://github.com/jmazzi/crypt_keeper gem encrypts all attributes and all rows in db with the same key
# this extension to use different encryption for each attribute and each row
module ActiveRecordExtensions

  extend ActiveSupport::Concern

  # these 3 methods must be replaces by model specific implementations
  protected
  def encrypt_pk
    self.gift_id
  end
  def encrypt_pk=(new_encrypt_pk_value)
    self.gift_id = new_encrypt_pk_value
  end
  def new_encrypt_pk
    loop do
      temp_gift_id = String.generate_random_string(20)
      return temp_gift_id unless Gift.find_by_gift_id(temp_gift_id)
    end
  end

  # general methods for attribute encryption

  # check correct input type before assigning value to attribute (Ruby types in model / encrypted text in db)
  protected
  def check_type (attributename, attributevalue, classname)
    return unless attributevalue
    return if ((attributevalue.class.name == classname) or (classname == 'Bignum' and attributevalue.class.name == 'Fixnum'))
    # logger.debug2 "attributename.class.name = #{attributename.class.name} (#{attributename.class.name.class})"
    # logger.debug2 "classname = #{classname} (#{classname.class})"
    raise TypeError, "Invalid type #{attributename.class.name} for attribute #{attributename}. " +
        "Allowed types are NilClass and #{classname}"
  end # check_type

  # encrypt_add_pre_and_postfix and encrypt_remote_pre_and_postfix to de used in get/set attribute methods
  protected
  def encrypt_rand_seed (attributename, secret_key_no)
    self.encrypt_pk = self.new_encrypt_pk unless self.encrypt_pk
    hex = Digest::MD5.hexdigest(encrypt_pk + ENCRYPT_KEYS[secret_key_no] + attributename)
    hex.to_i(16)
  end # rand_seed

  def encrypt_prefix (r, attributename, secret_key_no)
    prefix_lng = r.rand(20)+1
    chars = ENCRYPT_KEYS[secret_key_no].split('')
    temp_prefix = ""
    1.upto(prefix_lng) { temp_prefix << chars[r.rand(chars.size-1)] }
    temp_prefix
  end

  def encrypt_postfix (r, attributename, secret_key_no)
    postfix_lng = r.rand(20)+1
    chars = ENCRYPT_KEYS[secret_key_no].split('')
    temp_postfix = ''
    1.upto(postfix_lng) { temp_postfix << chars[r.rand(chars.size-1)] }
    temp_postfix
  end

  def encrypt_add_pre_and_postfix(value, attributename, secret_key_no)
    debug_attributes = %w()
    r = Random.new encrypt_rand_seed(attributename, secret_key_no)
    o = "#{encrypt_prefix(r, attributename, secret_key_no)}#{value}#{encrypt_postfix(r, attributename, secret_key_no)}"
    if debug_attributes.index(attributename)
      logger.debug2  "encrypt_add_pre_and_postfix: input = \"#{value}\" (#{value.class.name}), output = \"#{o}\" (#{o.class.name})"
    end
    o
  end # encrypt_add_pre_and_postfix

  # problem with response from crypt_keeper
  # ActionView::Template::Error (incompatible character encodings: ASCII-8BIT and UTF-8)
  # https://github.com/jmazzi/crypt_keeper/issues/50
  # temporary solution: add .force_encoding("UTF-8") in views
  def encrypt_remove_pre_and_postfix(value, attributename, secret_key_no)
    debug_attributes = %w()
    if debug_attributes.index(attributename)
      logger.debug2  "encrypt_remove_pre_and_postfix: class = #{self.class}, id = #{id} (#{id.class})"
      logger.debug2  "encrypt_remove_pre_and_postfix: value = #{value} (#{value.class})"
      logger.debug2  "encrypt_remove_pre_and_postfix: attributename = #{attributename} (#{attributename.class})"
      logger.debug2  "encrypt_remove_pre_and_postfix: secret_key_no = #{secret_key_no} (#{secret_key_no.class})"
    end
    r = Random.new encrypt_rand_seed(attributename, secret_key_no)
    prefix_lng = encrypt_prefix(r, attributename, secret_key_no).size
    postfix_lng = encrypt_postfix(r, attributename, secret_key_no).size
    value_lng = value.size
    from = prefix_lng
    to = value_lng - postfix_lng - 1
    o = value[from..to]
    if debug_attributes.index(attributename)
      logger.debug2  "encrypt_remove_pre_and_postfix: attribute = #{attributename}, input = \"#{value}\" (#{value.class.name}), output = \"#{o}\" (#{o.class.name})"
    end
    return nil unless o
    o.force_encoding('UTF-8')
  end # encrypt_remove_pre_and_postfix

  def str_to_float_or_nil (str)
    return nil if str.to_s == ''
    str.to_f
  end

  module ClassMethods

    # https://gist.github.com/danieldbower/842562
    # Logic for forking connections
    # The forked process does not have access to static vars as far as I can discern, so I've done some stuff to check if the op threw an exception.
    def fork_with_new_connection
      # Store the ActiveRecord connection information
      config = ActiveRecord::Base.remove_connection

      pid = fork do
        # tracking if the op failed for the Process exit
        success = true

        begin
          ActiveRecord::Base.establish_connection(config)
          # This is needed to re-initialize the random number generator after forking (if you want diff random numbers generated in the forks)
          srand

          # Run the closure passed to the fork_with_new_connection method
          yield

        rescue => exception
          logger.debug2  ('Forked operation failed with exception: ' + exception)
          # the op failed, so note it for the Process exit
          success = false

        ensure
          ActiveRecord::Base.remove_connection
          Process.exit! success
        end
      end

      # Restore the ActiveRecord connection information
      ActiveRecord::Base.establish_connection(config)

      #return the process id
      pid
    end  # fork_with_new_connection

    # interest calculation - different interest for positive and negative amount - see constants.rb
    def calculate_new_price(amount, days)
      return amount if amount == NilClass or amount == 0 or amount == 0.0
      return amount * FACTOR_POS_BALANCE_PER_DAY ** days if amount > 0
      return amount * FACTOR_NEG_BALANCE_PER_DAY ** days if amount < 0
      amount
    end

  end # ClassMethods

end