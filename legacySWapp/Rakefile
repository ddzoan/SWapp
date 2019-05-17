require 'active_record'
require 'yaml'
 
task :default => :migrate
 
desc "Migrate the database through scripts in db/migrate. Target specific version with VERSION=x"
task :migrate => :environment do
  ActiveRecord::Migrator.migrate('db/migrate', ENV["VERSION"] ? ENV["VERSION"].to_i : nil )
end

task :schema_dump => :environment do
  #Rake::Task["db:schema:dump"].invoke if ActiveRecord::Base.schema_format == :ruby
  require 'active_record/schema_dumper'
  filename = './db/schema.rb'
  File.open(filename, "w:utf-8") do |file|
    ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, file)
  end
end

desc 'Load a schema.rb file into the database'
task :load => :environment do
  ActiveRecord::Tasks::DatabaseTasks.load_schema_current(:ruby, ENV['SCHEMA'])
end
                
task :environment do
  ActiveRecord::Base.establish_connection(YAML::load(File.open('database.yml')))
  ActiveRecord::Base.logger = Logger.new(File.open('database.log', 'a'))
end
