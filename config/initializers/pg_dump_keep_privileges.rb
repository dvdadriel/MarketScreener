# See config/application.rb: config.active_record.schema_format = :sql.
#
# Rails' PostgreSQL structure dump hardcodes `--no-privileges` when shelling
# out to pg_dump. That silently drops the `GRANT SELECT ... TO anon;`
# statements added by db/migrate/20260828120200_add_anon_read_policies_for_dashboard.rb.
# Without those grants, a from-scratch `db:schema:load` reproduces the RLS
# policies (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY` and `CREATE POLICY`
# do get dumped) but the `anon` role still can't touch the tables at all —
# RLS policies only restrict which rows a role can see once it already has
# table-level privilege; they don't grant that privilege. A first-time
# `db:prepare` on a fresh Supabase project would therefore look secure
# (relrowsecurity = t) while being completely broken for the app's
# anon-read dashboard use case.
#
# Strip that flag before pg_dump runs so structure.sql keeps the explicit
# grants. Table/view owners' implicit privileges are not re-dumped as
# explicit GRANT statements, so this only reintroduces the grants this app
# actually created. Do not remove this without also re-adding the GRANT
# statements to structure.sql some other way.
ActiveSupport.on_load(:active_record) do
  require "active_record/tasks/postgresql_database_tasks"

  ActiveRecord::Tasks::PostgreSQLDatabaseTasks.prepend(Module.new do
    def run_cmd(cmd, *args, **opts)
      args = args.reject { |a| a == "--no-privileges" } if cmd == "pg_dump"
      super(cmd, *args, **opts)
    end
  end)
end
