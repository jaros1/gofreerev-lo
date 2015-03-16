class SystemParameter < ActiveRecord::Base


  # 1 - name - String in model and database
  
  # 2 - value - String in model - base64 encoded in database
  def value
    return nil unless (extended_value = read_attribute(:value))
    Base64.decode64(extended_value)
  end # value
  def value=(new_value)
    if new_value
      # logger.debug2  "new_value = #{new_value} (#{new_value.class.name})"
      write_attribute :value, Base64.encode64(new_value)
    else
      write_attribute :value, nil
    end
  end # value=
  alias_method :value_before_type_cast, :value
  def value_was
    return value unless value_changed?
    return nil unless (extended_value = attribute_was(:value))
    Base64.decode64(extended_value)
  end # value_was

  # setup distributed server network
  # this server can connect to other gofreerev servers as client
  # other gofreerev servers can connect to this gofreerev as clients
  def self.generate_key_pair
    # generate and save public/private key pair
    SystemParameter.where(:name => %w(public_key private_key)).delete_all
    k = SSHKey.generate
    # save public key - not encrypted
    s = SystemParameter.new
    s.name = 'public_key'
    s.value = k.public_key
    s.save!
    # save private key - encrypted with 1-5 passwords - see config/initializers/constants.rb
    x = k.private_key
    [PK_PASS_1_ENV, PK_PASS_2_RAILS, PK_PASS_3_DB, PK_PASS_4_FILE, PK_PASS_5_MEM].each do |password|
      x = x.encrypt(:symmetric, :password => password) if password
    end
    s = SystemParameter.new
    s.name = 'private_key'
    s.value = x
    s.save!
    # create/update did (unique device id) - new key pair = new did
    s = SystemParameter.find_by_name('did')
    if !s
      s = SystemParameter.new
      s.name = 'did'
    end
    s.value = (Time.now.to_f.to_s + rand().to_s.last(7)).gsub('.','').first(20)
    s.save!
    # create/update client secret. used as secret part of device.sha256
    # did+sha256 is mailbox address in client to client communication
    s = SystemParameter.find_by_name('secret')
    if !s
      s = SystemParameter.new
      s.name = 'secret'
    end
    s.value = rand().to_s.last(10)
    s.save!
    # create/update sid (unique session id). used in ping request
    s = SystemParameter.find_by_name('sid')
    if !s
      s = SystemParameter.new
      s.name = 'sid'
    end
    s.value = (Time.now.to_f.to_s + rand().to_s.last(7)).gsub('.','').first(20)
    s.save!
    nil
  end

  def self.public_key
    s = SystemParameter.find_by_name('public_key')
    return nil unless s
    s.value
  end

  def self.private_key
    s = SystemParameter.find_by_name('private_key')
    return nil unless s
    # decrypt
    x = s.value
    [PK_PASS_1_ENV, PK_PASS_2_RAILS, PK_PASS_3_DB, PK_PASS_4_FILE, PK_PASS_5_MEM].reverse.each do |password|
      x = x.decrypt(:symmetric, :password => password) if password
    end
    x
  end

  def self.did
    s = SystemParameter.find_by_name('did')
    s ? s.value : nil
  end

  def self.sid
    s = SystemParameter.find_by_name('sid')
    s ? s.value : nil
  end

  def self.secret
    s = SystemParameter.find_by_name('secret')
    s ? s.value : nil
  end

end
