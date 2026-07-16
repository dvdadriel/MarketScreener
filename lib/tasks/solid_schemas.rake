namespace :db do
  namespace :schema do
    namespace :load do
      desc "Load solid_queue schema into queue database"
      task queue: :environment do
        ActiveRecord::Base.establish_connection(:queue)
        load(Rails.root.join("db/queue_schema.rb"))
        puts "Loaded queue_schema.rb"
      end

      desc "Load solid_cache schema into cache database"
      task cache: :environment do
        ActiveRecord::Base.establish_connection(:cache)
        load(Rails.root.join("db/cache_schema.rb"))
        puts "Loaded cache_schema.rb"
      end

      desc "Load solid_cable schema into cable database"
      task cable: :environment do
        ActiveRecord::Base.establish_connection(:cable)
        load(Rails.root.join("db/cable_schema.rb"))
        puts "Loaded cable_schema.rb"
      end

      desc "Load all solid schemas"
      task solid: %i[queue cache cable]
    end
  end
end
