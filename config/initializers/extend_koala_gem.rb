# config default oauth version when communicating with facebook API
# note that friends list only include app users in oauth 2.x versions
# that is empty for most users
Koala.config.api_version = 'v2.2'

# output debug info in development environments
Koala::Utils.logger.level = Logger::DEBUG unless FORCE_SSL

# dump unexpected facebook/koala exceptions to log for easier debugging
class Koala::Facebook::APIError
  # inject rails logger into Koala exceptions
  def logger=(new_logger)
    @logger = new_logger
  end
  def logger
    @logger
  end
end

class Koala::Facebook::ClientError
  def puts_exception (prefix=nil)
    if !logger
      puts "Warning. No logger was found for Koala::Facebook::ClientError exception"
      return
    end
    logger.debug2  "#{prefix}Koala::Facebook::ClientError"
    logger.debug2  "#{prefix}fb_error_type    = #{fb_error_type} (#{fb_error_type.class})"
    logger.debug2  "#{prefix}fb_error_code    = #{fb_error_code} (#{fb_error_code.class})"
    logger.debug2  "#{prefix}fb_error_subcode = #{fb_error_subcode} (#{fb_error_subcode.class})"
    logger.debug2  "#{prefix}fb_error_message = #{fb_error_message} (#{fb_error_message.class})"
    logger.debug2  "#{prefix}http_status      = #{http_status} (#{http_status.class})"
    logger.debug2  "#{prefix}response_body    = #{response_body}"
  end
end

class Koala::Facebook::ServerError
  def puts_exception (prefix=nil)
    if !logger
      puts "Warning. No logger was found for Koala::Facebook::ServerError exception"
      return
    end
    logger.debug2  "#{prefix}Koala::Facebook::ServerError"
    logger.debug2  "#{prefix}fb_error_type    = #{fb_error_type} (#{fb_error_type.class})"
    logger.debug2  "#{prefix}fb_error_code    = #{fb_error_code} (#{fb_error_code.class})"
    logger.debug2  "#{prefix}fb_error_subcode = #{fb_error_subcode} (#{fb_error_subcode.class})"
    logger.debug2  "#{prefix}fb_error_message = #{fb_error_message} (#{fb_error_message.class})"
    logger.debug2  "#{prefix}http_status      = #{http_status} (#{http_status.class})"
    logger.debug2  "#{prefix}response_body    = #{response_body}"
  end
end