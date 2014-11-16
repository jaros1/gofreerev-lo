GofreerevFb::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports and disable caching.
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations
  config.active_record.migration_error = :page_load

  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true

  # exception_notification gem
  config.action_mailer.delivery_method = :sendmail
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  # get smtp config from environment variables <env>_EN_EMAIL_PREFIX. EN = exception notification
  rails_env = case Rails.env when "development" then "DEV" when "test" then "TEST" when "production" then "PROD" end
  config.middleware.use ExceptionNotification::Rack,
                        :email => {
                            :email_prefix => ENV["gofreerev_#{rails_env}_en_email_prefix".upcase],
                            :sender_address => ["notifier", ENV["gofreerev_#{rails_env}_en_sender".upcase]],
                            :exception_recipients => ENV["gofreerev_#{rails_env}_en_recipients".upcase].to_s.split(' '),
                            :delivery_method => :smtp,
                            :smtp_settings => {
                                :address => ENV["gofreerev_#{rails_env}_en_address".upcase],
                                :port => 587,
                                :authentication => 'plain',
                                :enable_starttls_auto => true,
                                :domain => ENV["gofreerev_#{rails_env}_en_domain".upcase],
                                :user_name => ENV["gofreerev_#{rails_env}_en_user_name".upcase],
                                :password => ENV["gofreerev_#{rails_env}_en_password".upcase],
                            }
                        }
end
