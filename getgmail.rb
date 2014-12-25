require 'net/imap'
require 'mail'
require 'active_record'
require 'optparse'
require 'net/smtp'
require 'logger'

require './email_parser.rb'

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

def send_email(type, recipient, subject, messagedata)
  case type
  when :confirmation
    message = "From: ICheckYouIn <#{$options[:login]}>\nTo: <#{recipient}>\n" +
      "Subject: #{subject}\n" +
      "Your checkin has been logged.\n" +
      "First Name: #{messagedata[:firstname]}\n" +
      "Last Name: #{messagedata[:lastname]}\n" +
      "Confirmation Number: #{messagedata[:confirmation]}\n" +
      "Checkin Time in Pacific Time: #{messagedata[:checkintime].localtime}"
  when :delete
    message = "From: ICheckYouIn <#{$options[:login]}>\nTo: <#{recipient}>\n" +
      "Subject: #{subject}\n" +
      "The following checkin is being DELETED due to duplicate confirmation number. You will receive a confirmation email for the replacement flight\n" +
      "First Name: #{messagedata[:firstname]}\n" +
      "Last Name: #{messagedata[:lastname]}\n" +
      "Confirmation Number: #{messagedata[:confirmation]}\n" +
      "Checkin Time in Pacific Time: #{messagedata[:checkintime].localtime}"
  when :error
    message = "From: ICheckYouIn <#{$options[:login]}>\nTo: <#{recipient}>\n" +
      "Subject: #{subject}\n" +
      "Error message is below \n\n#{messagedata[:message]}"
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

def log_data()
  mailIds = $imap.search(['ALL'])
  mailIds.each do |id|
    envelope = $imap.fetch(id, "ENVELOPE")[0].attr["ENVELOPE"]

    # using net/imap
    msg = $imap.fetch(id,'RFC822')[0].attr['RFC822']
    # using Mail object
    email = Mail.new(msg)
    subject = email.subject
    sender = email.from.first
    
    # catch exceptions if necessary checkin data is not found
    begin
    
    raise EmailScrape::EmailFromSouthwest if sender.downcase.include?('southwest')

    received_date = email.date
    if email.multipart?
      body = email.html_part.body.decoded
    else
      body = email.body.decoded
    end

    confnum, checkin_hashes = email_parser(body, sender)

    # Delete any old entries with the same confirmation num. Assumption: only updated itineraries will be sent in and old entries deleted
    # Someone who knows other confirmation numbers could potentially delete entries
    ActiveRecord::Base.connection_pool.with_connection do
      Checkindata.where(confnum: confnum).each do |ci|
        send_email(:delete, ci.email_sender, "DELETING checkin for #{ci.firstname} #{ci.lastname}", {firstname: ci.firstname,lastname: ci.lastname,confirmation: ci.confnum, checkintime: ci.time})
        ci.delete
      end
    end

    checkin_hashes.each do |checkindata|

      ActiveRecord::Base.connection_pool.with_connection do
        Checkindata.create(checkindata)
      end

      send_email(:confirmation, sender, "re: #{subject}", {firstname: checkindata[:firstname], lastname: checkindata[:lastname], confirmation: checkindata[:confnum], checkintime: checkindata[:time]})
    end

    # move email to logged folder
    $imap.copy(id, "logged")
    $imap.store(id, "+FLAGS", [:Deleted])

    puts "copied #{id} #{subject} to logged and flagged for deletion" if $debug

    rescue EmailScrape::Error => e
      puts "#{e.message}. Moving it to errors folder!"
      $logger.error("#{e.message}. Moving it to errors folder!")
      # File.open('errors/emailscrape/log.txt', 'a') { |file| file.write(Time.now.to_s + ' ' + e.message + ' "' + subject + "\"\n") }

      send_email(:notifydan,$options[:notify], "Bad southwest email received", {message: "A message was moved to the errors folder \n\n#{e.message}\n\n#{e.backtrace}"})
      if !sender.downcase.include?("southwest")
        send_email(:error,sender, "re: #{subject}", {message: "An error has occurred while trying to log your data. \n\n#{e.message}"})
      end
      
      $imap.copy(id, "errors")
      $imap.store(id, "+FLAGS", [:Deleted])
        
      puts "copied #{id} to errors and flagged for deletion" if $debug
    end
  end

  $imap.expunge
end

starttime = Time.now
logins = 0

begin
  if $options[:login] && $options[:password] && $options[:notify]
    puts "Starting Gmail checker"
    while true
      begin
        logins += 1
        $imap = Net::IMAP.new('imap.gmail.com', ssl: true)
        $imap.login($options[:login], $options[:password])
        $imap.select('INBOX')

        log_data()

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
  send_email(:notifydan,$options[:notify], "Gmail Checker Crashed", {message: "gmail checker crashed \n\n#{e.message}\n\n#{e.backtrace}"})
  $logger.fatal("Caught exception; exiting")
  $logger.fatal(e)
  message = "#{Time.now} #{e}"
  puts message
end
