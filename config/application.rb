require File.expand_path('../boot', __FILE__)

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(:default, Rails.env)

module GofreerevFb
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    I18n.enforce_available_locales = true
    config.i18n.available_locales = [:en, :da]
    config.i18n.default_locale = :en

    # Custom directories with classes and modules you want to be autoloadable.
    config.autoload_paths += %W(#{config.root}/lib)
    config.autoload_paths += %W(#{config.root}/lib/custom_exceptions)

    # config.assets.enabled = true
    # config.middleware.use I18n::JS::Middleware

    # enable dalli memory cache - used for temporary passwords in server to server communication
    # config.cache_store = :mem_cache_store, 'localhost', {:namespace => config.root, :expires_in => 1.hour }
    config.cache_store = :mem_cache_store, 'localhost', {:namespace => config.root }
  end
end