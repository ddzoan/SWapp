require 'net/imap'
require 'nokogiri'
require 'mail'
require 'active_record'

load 'airportdata/airporthash.rb'
# use global var $timezone["AAA"] to get time zone, replace AAA with airport code
$debug = false

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

def sw_date_breakdown(date)
  months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
  month = months.index(date.split[1]).to_i + 1
  day = date.split.last.to_i

  if month >= Time.now.month && day >= Time.now.day
    year = Time.now.year
  else
    year = Time.now.year + 1
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

def name_conversion(name)
  lastname = name.split('/')[0]
  firstname = name.split('/')[1].split(' ').first

  return [firstname,lastname]
end

def log_data()
  mailIds = $imap.search(['ALL'])
  mailIds.each do |id|
    envelope = $imap.fetch(id, "ENVELOPE")[0].attr["ENVELOPE"]
    subject = envelope['subject']
    sender = envelope.from[0].mailbox + '@' + envelope.from[0].host
    received_date = envelope['date']

    # using net/imap
    msg = $imap.fetch(id,'RFC822')[0].attr['RFC822']
    # using Mail object
    email = Mail.new(msg)
    body = email.html_part.body.decoded
    emailhtml = Nokogiri::HTML(body)
    emailtext = emailhtml.text

    # catch exceptions if necessary checkin data is not found
    begin

    find_conf = emailhtml.search "[text()*='AIR Confirmation']"
    if find_conf.empty?
      raise EmailScrape::ConfirmationError
    end

    confirmation = find_conf[0].last_element_child.child.text.strip

    # Delete any old entries with the same confirmation num. Assumption: only updated itineraries will be sent in and old entries deleted
    # Someone who knows other confirmation numbers could potentially delete entries
    ActiveRecord::Base.connection_pool.with_connection do
      Checkindata.where(confnum: confirmation).each do |checkin|
        # email person before deleting their checkin?
        checkin.delete
      end
    end

    find_name = emailhtml.search "[text()*='Passenger(s)']"
    if find_name.empty?
      raise EmailScrape::NameError
    end
    
    name = find_name[0].parent.parent.parent.parent.parent.next_element.css('div').first.text.strip

    firstname,lastname = name_conversion(name)

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
        departurecity = find_date.parent.next_element.next_element.css('div div')[0].css('b')[0].text
        departurecitycode = find_date.parent.next_element.next_element.css('div div')[0].text.scan(/\((\w{3})\)/).first.first
        departuretime = find_date.parent.next_element.next_element.css('div div')[0].css('b')[1].text
        arrivalcity = find_date.parent.next_element.next_element.css('div div')[1].css('b')[0].text
        arrivalcitycode = find_date.parent.next_element.next_element.css('div div')[1].text.scan(/\((\w{3})\)/).first.first
        arrivaltimetext = find_date.parent.next_element.next_element.css('div div')[1].css('b')[1].text

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
        end
      end
    end

    # move email to logged folder
    $imap.copy(id, "logged")
    $imap.store(id, "+FLAGS", [:Deleted])

    puts "copied #{id} #{subject} to logged and flagged for deletion" if debug

    rescue EmailScrape::Error => e
      puts "#{e.message}. Moving it to errors folder!"
      File.open('errors/emailscrape/log.txt', 'a') { |file| file.write(Time.now.to_s + ' ' + e.message + ' "' + subject + "\"\n") }
      
      $imap.copy(id, "errors")
      $imap.store(id, "+FLAGS", [:Deleted])
        
      puts "copied #{id} to errors and flagged for deletion" if debug
    end
  end

  $imap.expunge
end

while true
  $imap = Net::IMAP.new('imap.gmail.com', ssl: true)
  $imap.login('icheckyouin@gmail.com', ARGV.last)
  $imap.select('INBOX')

  log_data()

  $imap.logout
  $imap.disconnect
  sleep 5
end