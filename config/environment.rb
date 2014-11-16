# Load the Rails application.
require File.expand_path('../application', __FILE__)

class ActiveSupport::Logger
  def debug2 (text)
    debug "#{caller_locations(1,1)[0].label}: #{text}"
  end
  def secret2 (text) # used for special protected information - for example token - disabled on public web servers
    debug "#{caller_locations(1,1)[0].label}: #{text}" unless FORCE_SSL
  end
  def info2 (text)
    info "#{caller_locations(1,1)[0].label}: #{text}"
  end
  def warn2 (text)
    warn "#{caller_locations(1,1)[0].label}: #{text}"
  end
  def error2 (text)
    error "#{caller_locations(1,1)[0].label}: #{text}"
  end
  def fatal2 (text)
    fatal "#{caller_locations(1,1)[0].label}: #{text}"
  end
end

# Extend String
class String
  # random string - for keys, state etc
  def self.generate_random_string (lng)
    chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
    newpass = ''
    1.upto(lng) { newpass << chars[rand(chars.size-1)] }
    newpass
  end # generate_random_string
  # used in views with language texts that can be String or arrays of String
  def each
    yield self
  end
  def yyyymmdd?
    return false unless self =~ /^20[0-9]{2}[0-1][0-9][0-3][0-9]$/
    begin
      Date.parse(self)
    rescue ArgumentError => e
      return false
    end
    (self <= Date.today.to_yyyymmdd)
  end # yyyymmdd?
end # String

# Implement find_usertype. Only relevant for Hash, but must exists as dummy methods in String and Array
# usertype is first two characters in user_id. That is FB, GP etc
# used in views to allow different texts in views for different login API's
# Hash: returns hash[usertype], hash[hash.keys.first] or []
class String
  def find_usertype(usertype)
    self
  end
end
class Array
  def find_usertype (usertype)
    self
  end
end
class Hash
  def find_usertype (usertype)
    return self[nil] if usertype == nil and self.has_key?(nil)
    for i in 1 .. 3 do loop
      key = case i
              when 1 then usertype
              when 2 then usertype.downcase
              when 3 then usertype.upcase
            end
      return self[key] if self.has_key?(key)
      key = case key.class.name
              when 'String' then key.to_sym ;
              when 'Symbol' then key.to_s
              else key
            end
      return self[key] if self.has_key?(key)
    end unless usertype == nil
    key = self.keys.first
    return [] unless key
    self[key]
  end # find_usertype (usertype)
end # find_usertype

# used in last_money_bank_request sequence
class Time
  def self.current_hour_no
    (Time.new.to_i/60-23000000).to_i
  end
  def to_yyyymmdd
    self.strftime("%Y%m%d")
  end
end

class Date
  def to_yyyymmdd
    self.strftime("%Y%m%d")
  end
end

# Initialize the Rails application.
GofreerevFb::Application.initialize!

# todo: check login provider setup