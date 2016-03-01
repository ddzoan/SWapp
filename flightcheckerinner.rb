require 'active_record'
require 'yaml'
require './checkinclass.rb'
require 'logger'

require 'optparse'
require 'net/smtp'

$options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: getgmail.rb [options]"

  opts.on("-u", "--user USERNAME", "Require username") do |l|
    $options[:login] = l
  end

  opts.on("-p", "--pass PASSWORD", "Require password") do |p|
    $options[:password] = p
  end

  opts.on("-n", "--notif ADMIN", "Require admin email for notifications") do |n|
    $options[:notify] = n
  end
end.parse!

$logger = Logger.new('logs/flightcheckerinner.log')

$logger.level = Logger::INFO

dbconfig = YAML::load(File.open('database.yml'))
ActiveRecord::Base.establish_connection(dbconfig)

begin
  if $options[:login] && $options[:password] && $options[:notify]
    puts "Starting Flight Checker Inner. #{Time.now}"

    while true do
      ActiveRecord::Base.connection_pool.with_connection do
        Checkindata.where(checkedin: false).order(:time).each do |checkindata|
          if checkindata.tryToCheckin?
            checkindata.flight_checkin
          end
        end
      end
    end
  else
    puts "You must enter a USERNAME and PASSWORD as command line arguments.\nUsage: getgmail.rb [options]"
    puts " -u, --user USERNAME              Require username"
    puts " -p, --pass PASSWORD              Require password"
    puts " -n, --notif ADMIN                Require admin email for notifications"
  end
rescue => e
  $logger.fatal("Caught exception; exiting")
  $logger.fatal(e)
  message = "#{Time.now} #{e}"
  puts message
  send_email(:notifydan,$options[:notify], "Flight Checker Inner Crashed", {message: "flight checker inner crashed \n\n#{e.message}\n\n#{e.backtrace}"})
end

def send_email(type, recipient, subject, messagedata)
  case type
  when :notifydan
    message = "From: ICheckYouIn <#{$options[:login]}>\nTo: <#{recipient}>\n" +
      "Subject: #{subject}\n" +
      "Error message is below\n\n#{messagedata[:message]}"
  end

  smtp = Net::SMTP.new 'smtp.gmail.com', 587
  smtp.enable_starttls
  smtp.start('gmail.com', $options[:login], $options[:password], :login)
  smtp.send_message(message, $options[:login], recipient)
  smtp.finish
end
