require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module CryptoScreener
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = "UTC"
    config.active_job.queue_adapter = :solid_queue

    # Several migrations use raw `execute(...)` SQL for RLS policies, grants,
    # and views (see db/migrate/20260828*). The Ruby schema dumper silently
    # drops all of that, which would leave a fresh `db:prepare` with no RLS,
    # no policies, and no views. SQL format (structure.sql via pg_dump)
    # faithfully captures it. Do NOT switch this back to :ruby.
    config.active_record.schema_format = :sql
  end
end
