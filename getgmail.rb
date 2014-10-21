require 'net/imap'
require 'nokogiri'
require 'mail'
require 'active_record'
require 'optparse'
require 'net/smtp'
require 'logger'

require './airportdata/airporthash.rb'
# use global var $timezone["AAA"] to get time zone, replace AAA with airport code
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

class EmailScrape
  class Error < RuntimeError
  end

  class EmailFromSouthwest < Error
    def initialize(message = "Email is from southwest.com, not logging")
      super(message)
    end
  end

  class NotSouthwestError < Error
    def initialize(message = "Did not find 'southwest.com' text in email")
      super(message)
    end
  end

  class ConfirmationError < Error
    def initialize(message = "Can't find 'AIR Confirmation' in email")
      super(message)
    end
  end

  class NameError < Error
    def initialize(message = "Can't find 'Passenger(s)' in email")
      super(message)
    end
  end

  class DateError < Error
    def initialize(message = "Can't find any flight dates")
      super(message)
    end
  end
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

def sw_date_breakdown(date)
  months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
  month = months.index(date.split[1]).to_i + 1

  weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  day = date.split.last.to_i
  
  # this checks if the day of the week, month, and date combo is from the current year or the next
  # the assumption is that no one would book a flight more than a year in advance
  if Time.new(Time.now.year, month, day).wday == weekdays.index(date.split.first)
    year = Time.now.year
  elsif Time.new(Time.now.year + 1, month, day).wday == weekdays.index(date.split.first)
    year = Time.now.year + 1
  else
    raise DateError, "The month and date does not occur this year or next year"
  end

  return [year, month, day]
end

def date_breakdown(date)
  month = date.split('/')[0]
  day = date.split('/')[1]
  year = date.split('/')[2]
  return [month, day, year]
end

def time_convertion(time, offset)
  hour = time.split(':')[0].to_i
  min = time.split(' ')[0].split(':').last.to_i
  ampm = time.split(' ').last

  hour = hour + 12 if ampm == "PM" && hour < 12

  hour = hour + $timezone['SFO'].to_i - offset.to_i

  return [hour,min]
end

def get_checkin_time(flytime)
  checkintime = flytime - 60*60*24
  if checkintime.dst? == flytime.dst?
    return checkintime
  else
    if flytime.dst?
      return checkintime + 60*60
    else
      return checkintime - 60*60
    end
  end
end

# Assumes if name has "/" in it, then it is formatted Last/First Middle and if it does not,
# then it is formatted First Middle Last
def name_conversion(name)
  if name.include?('/')
    lastname = name.split('/')[0]
    firstname = name.split('/')[1].split(' ').first
  else
    firstname = name.split.first
    lastname = name.split.last
  end

  if !firstname.nil? && !lastname.nil?
    return [firstname,lastname]
  else
    raise EmailScrape::NameError.new("Name Conversion failure")
  end
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
    emailhtml = Nokogiri::HTML(body)
    emailtext = emailhtml.text

    if !emailtext.include?("southwest.com")
      raise EmailScrape::NotSouthwestError
    end

    find_conf = emailhtml.search "[text()*='AIR Confirmation']"
    find_name = emailhtml.search "[text()*='Passenger(s)']"

    if find_name.empty?
      raise EmailScrape::NameError
    end

    # This deals with 2 different types of formatting that Southwest gives in their confirmation emails.
    # If the confirmation number is not found through the more common method, it searches assuming the other format.
    # The name placement is dependent on this formatting so the relative element is found after determining the confirmation format.
    if find_conf.empty?
      find_conf = emailhtml.search "[text()*='Air Confirmation']"
      confirmation = find_conf[0].parent.parent.parent.parent.parent.next_element.css('div').first.text.strip
  
      name = find_name[0].parent.parent.parent.parent.parent.next_element.css('div').last.text.strip
    else
      confirmation = find_conf[0].last_element_child.child.text.strip

      name = find_name[0].parent.parent.parent.parent.parent.next_element.css('div').first.text.strip
    end

    if find_conf.empty?
      raise EmailScrape::ConfirmationError
    end

    firstname,lastname = name_conversion(name)

    # Delete any old entries with the same confirmation num. Assumption: only updated itineraries will be sent in and old entries deleted
    # Someone who knows other confirmation numbers could potentially delete entries
    ActiveRecord::Base.connection_pool.with_connection do
      Checkindata.where(confnum: confirmation).each do |ci|
        send_email(:delete, ci.email_sender, "DELETING checkin for #{ci.firstname} #{ci.lastname}", {firstname: ci.firstname,lastname: ci.lastname,confirmation: ci.confnum, checkintime: ci.time})
        ci.delete
      end
    end

    flight_dates = emailtext.scan(/(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d\d?/)

    if flight_dates.empty?
      raise EmailScrape::DateError
    end

    # Convert array to set to remove duplicates. Any duplicate dates (e.g. 2 flights 1 day) are handled in the each below
    flight_dates = flight_dates.to_set

    flight_dates.each do |date|
      # if you have found the date already, you can use search and then find the corresponding data in the table
      find_dates = emailhtml.search "[text()*='#{date}']"
      find_dates.each do |find_date|
        flightnumber = find_date.parent.next_element.text.strip
        departure_elements = find_date.parent.next_element.next_element

        departurecity = departure_elements.css('div')[0].css('b')[0].text
        departurecitycode = departure_elements.css('div')[0].text.scan(/\((\w{3})\)/).first.first
        departuretime = departure_elements.css('div')[0].css('b')[1].text
        arrivalcity = departure_elements.css('div')[0].css('b')[2].text
        arrivalcitycode = departure_elements.css('div')[0].text.scan(/\((\w{3})\)/).last.first
        arrivaltimetext = departure_elements.css('div')[0].css('b')[3].text

        year,month,day = sw_date_breakdown(date)
        
        departurezone = $timezone[departurecitycode]
        hour,min = time_convertion(departuretime, departurezone)

        arrivalzone = $timezone[arrivalcitycode]
        arrhour,arrmin = time_convertion(arrivaltimetext, arrivalzone)
        arrivaltime = Time.new(year,month,day,arrhour,arrmin)

        flytime = Time.new(year, month, day, hour, min)
        checkintime = get_checkin_time(flytime)

        if $debug
          puts "#{flytime} #{name} | #{confirmation} | #{date} | #{flightnumber} | #{departurecitycode} at #{departuretime} #{departurezone} | #{arrivalcitycode} at #{arrivaltime}  #{$timezone["#{arrivalcitycode}"]}"
          puts "pacific time departure: #{hour}:#{min}"
          
          puts "db create:"
          puts "firstname: #{firstname}, lastname: #{lastname}, confnum: #{confirmation},time: #{checkintime}"
          puts "departing_airport: #{departurecitycode}, depart_time: #{flytime}"
          puts "arriving_airport: #{arrivalcitycode}, arrive_time: #{arrivaltime}, flight_number: #{flightnumber}"
        end

        ActiveRecord::Base.connection_pool.with_connection do
          Checkindata.create({firstname: firstname,
            lastname: lastname,
            confnum: confirmation,
            time: checkintime,
            departing_airport: departurecitycode,
            depart_time: flytime,
            arriving_airport: arrivalcitycode,
            arrive_time: arrivaltime,
            flight_number: flightnumber,
            email_sender: sender,
            conf_logged: Time.now})

          send_email(:confirmation, sender, "re: #{subject}", {firstname: firstname, lastname: lastname, confirmation: confirmation, checkintime: checkintime})
        end
      end
    end

    # move email to logged folder
    $imap.copy(id, "logged")
    $imap.store(id, "+FLAGS", [:Deleted])

    puts "copied #{id} #{subject} to logged and flagged for deletion" if $debug

    rescue EmailScrape::Error => e
      puts "#{e.message}. Moving it to errors folder!"
      File.open('errors/emailscrape/log.txt', 'a') { |file| file.write(Time.now.to_s + ' ' + e.message + ' "' + subject + "\"\n") }

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