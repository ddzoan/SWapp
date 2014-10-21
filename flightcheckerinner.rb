require 'active_record'
require 'mysql'
require 'yaml'
require './checkinclass.rb'
require 'logger'

$logger = Logger.new('swappcheckins.log')
$logger.level = Logger::INFO

dbconfig = YAML::load(File.open('database.yml'))
ActiveRecord::Base.establish_connection(dbconfig)

while true do
  ActiveRecord::Base.connection_pool.with_connection do
    Checkindata.where(checkedin: false).order(:time).each do |checkindata|
      if checkindata.tryToCheckin?
        checkindata.flight_checkin
      end
    end
  end
end