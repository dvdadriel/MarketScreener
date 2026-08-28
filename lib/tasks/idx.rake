namespace :idx do
  desc "Rekam regime + top-10 momentum harian, forward tracking (17:00 WIB)"
  task snapshot: :environment do
    MomentumSnapshotJob.perform_now
    DashboardSummaryMaterializer.new.call
  end
end
