require 'active_record'
require 'optparse'
require 'logger'

require './email_parser.rb'
require './swapp_helpers.rb'

$debug = false
$logger = Logger.new('logs/getgmail.log')
$logger.level = Logger::WARN

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

if !$debug
  dbconfig = YAML::load(File.open('database.yml'))
  ActiveRecord::Base.establish_connection(dbconfig)
else
  ActiveRecord::Base.establish_connection(
    :adapter => "sqlite3",
    :database => "checkins.db"
  )
end

class Checkindata < ActiveRecord::Base
end

starttime = Time.now
logins = 0

begin
  if $options[:login] && $options[:password] && $options[:notify]
    puts "Starting Gmail checker. #{Time.now}"
    while true
      begin
        logins += 1

        log_in
        log_data

        $imap.logout
        $imap.disconnect
        sleep 5
      rescue Net::IMAP::ByeResponseError => e
        # message = "ByeResponseError #{Time.now - starttime} seconds from start. Server has logged in #{logins} times. Sleeping 1 minute and then resetting starttime and logins."
        # puts message
        # File.open('gmailerrors.txt', 'a') { |file| file.write(message + "\n") }
        $logger.fatal("Caught known exception, sleep 60 and re-log in")
        $logger.fatal(e)
        sleep 60
        starttime = Time.now
        logins = 0
        # send_email(:notifydan,$options[:notify], "southwest gmail scrape error", {message: message} )
      rescue Errno::EPIPE => e
        # message = "#{e.message} error, #{Time.now - starttime} seconds from start. Server has logged in #{logins} times. Sleeping 1 minute and then resetting starttime and logins."
        # File.open('gmailerrors.txt', 'a') { |file| file.write(message + "\n") }
        $logger.fatal("Caught known exception, sleep 60 and re-log in")
        $logger.fatal(e)
        sleep 60
        starttime = Time.now
        logins = 0
      rescue Errno::ENETUNREACH => e
        $logger.fatal("Caught known exception, sleep 60 and re-log in")
        $logger.fatal(e)
        sleep 60
      rescue EOFError => e
      	$logger.fatal("Caught known exception, sleep 60 and re-log in")
      	$logger.fatal(e)
      	sleep 60
      rescue Net::IMAP::NoResponseError => e
        $logger.fatal("Caught known exception, sleep 60 and re-log in")
        $logger.fatal(e)
        sleep 60
      rescue SocketError => e
        $logger.fatal("Caught known exception, sleep 60 and re-log in")
        $logger.fatal(e)
        sleep 60
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
  send_email(:notifydan,$options[:notify], "Gmail Checker Crashed", {message: "gmail checker crashed \n\n#{e.message}\n\n#{e.backtrace}"})
end
