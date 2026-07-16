class InstallSolidSchemas < ActiveRecord::Migration[8.0]
  def up
    [ "queue_schema.rb", "cache_schema.rb", "cable_schema.rb" ].each do |file|
      path = Rails.root.join("db", file)
      next unless File.exist?(path)

      # Each schema file calls ActiveRecord::Schema.define which would normally
      # bump schema_migrations version. Suppress that by overriding the version arg.
      original = File.read(path)
      sanitized = original.sub(/ActiveRecord::Schema\[\d+\.\d+\]\.define\([^)]*\)/, "ActiveRecord::Schema.define")
      eval(sanitized)
    end
  end

  def down
    %w[
      solid_queue_blocked_executions
      solid_queue_claimed_executions
      solid_queue_failed_executions
      solid_queue_pauses
      solid_queue_processes
      solid_queue_ready_executions
      solid_queue_recurring_executions
      solid_queue_recurring_tasks
      solid_queue_scheduled_executions
      solid_queue_semaphores
      solid_queue_jobs
      solid_cache_entries
      solid_cable_messages
    ].each { |t| drop_table(t, if_exists: true) }
  end
end
