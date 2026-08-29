class EnableRlsDefaultDeny < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $$
      DECLARE r RECORD;
      BEGIN
        FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
        LOOP
          EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', r.tablename);
        END LOOP;
      END $$;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Sengaja tidak di-reverse otomatis — mematikan RLS lewat rollback berisiko " \
      "membuka semua tabel produksi ke anon tanpa sadar. Matikan manual per tabel kalau perlu."
  end
end
