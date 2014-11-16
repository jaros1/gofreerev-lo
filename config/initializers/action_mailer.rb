# Setup ActionMailer. ENV variables also used in ExceptionNotification (see development.rb)

ActionMailer::Base.delivery_method = :smtp

rails_env = case Rails.env when "development" then "DEV" when "test" then "TEST" when "production" then "PROD" end
ActionMailer::Base.smtp_settings = {:address => ENV["gofreerev_#{rails_env}_en_address".upcase],
                                    :port => 587,
                                    :domain => ENV["gofreerev_#{rails_env}_en_domain".upcase],
                                    :user_name => ENV["gofreerev_#{rails_env}_en_user_name".upcase],
                                    :password => ENV["gofreerev_#{rails_env}_en_password".upcase],
                                    :authentication => "plain",
                                    :enable_starttls_auto => true}
