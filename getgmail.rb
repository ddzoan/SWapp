require 'net/imap'
require 'nokogiri'
require 'mail'
require 'active_record'

load 'airportdata/airporthash.rb'
# use global var $timezone["AAA"] to get time zone, replace AAA with airport code

ActiveRecord::Base.establish_connection(
  :adapter => "sqlite3",
  :database => "checkins.db"
)

ActiveRecord::Schema.define do
  unless ActiveRecord::Base.connection.tables.include? 'checkindata'
    create_table :checkindata do |table|
      table.string :firstname
      table.string :lastname
      table.string :confnum
      table.datetime :time
      table.boolean :checkedin, default: false
      table.integer :attempts, default: 0
      table.integer :response_code
      table.string :resp_page_file
      table.string :response_name
      table.string :response_boarding
      table.string :checkin_time
      table.string :departing_airport
      table.datetime :depart_time
      table.string :arriving_airport
      table.time :arrive_time
      table.integer :flight_number
      table.datetime :conf_logged
    end
  end
end

class Checkindata < ActiveRecord::Base
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

imap = Net::IMAP.new('imap.gmail.com', ssl: true)
imap.login('icheckyouin@gmail.com', 'southwestcheckin4u')
imap.select('INBOX')

mailIds = imap.search(['ALL'])
mailIds.each do |id|
  name = ''
  confirmation = ''
  name_and_conf = false

  envelope = imap.fetch(id, "ENVELOPE")[0].attr["ENVELOPE"]
  subject = envelope['subject']
  received_date = envelope['date']
  
  if(subject.match(/Flight reservation \([\w]{6}\) \| \w{7} \| \w{3}-\w{3} \| \w+\/\w+[\s\w]*/))
    confirmation, subj_flight_date, name = subject.match(/Flight reservation \(([\w]{6})\) \| (\w{7}) \| \w{3}-\w{3} \| (\w+\/\w+[\s\w]*)/).captures
    name_and_conf = true
  end

  # using net/imap
  msg = imap.fetch(id,'RFC822')[0].attr['RFC822']
  # using Mail object
  email = Mail.new(msg)
  body = email.html_part.body.decoded
  emailhtml = Nokogiri::HTML(body)
  emailtext = emailhtml.text

  # catch exceptions if necessary checkin data is not found
  begin

  if !name_and_conf
    find_conf = emailhtml.search "[text()*='AIR Confirmation']"
    if find_conf.empty?
      raise "Can't find 'AIR Confirmation' in email"
    else
      confirmation = find_conf[0].last_element_child.child.text.strip
    end

    find_name = emailhtml.search "[text()*='Passenger(s)']"
    if find_name.empty?
      raise "Can't find 'Passenger(s)' in email"
    else
      name = find_name[0].parent.parent.parent.parent.parent.next_element.css('div').first.text.strip
    end
  end

  firstname,lastname = name_conversion(name)

  flight_dates = emailtext.scan(/(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) (?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d\d?/)

  if flight_dates.empty?
    raise "Can't find any flight dates"
  end

  flight_dates.each do |date|
    # if you have found the date already, you can use search and then find the corresponding data in the table
    find_date = emailhtml.search "[text()*='#{date}']"
    flightnumber = find_date[0].parent.next_element.text.strip
    departure_elements = find_date[0].parent.next_element.next_element
    departurecity = find_date[0].parent.next_element.next_element.css('div div')[0].css('b')[0].text
    departurecitycode = find_date[0].parent.next_element.next_element.css('div div')[0].text.scan(/\((\w{3})\)/).first.first
    departuretime = find_date[0].parent.next_element.next_element.css('div div')[0].css('b')[1].text
    arrivalcity = find_date[0].parent.next_element.next_element.css('div div')[1].css('b')[0].text
    arrivalcitycode = find_date[0].parent.next_element.next_element.css('div div')[1].text.scan(/\((\w{3})\)/).first.first
    arrivaltimetext = find_date[0].parent.next_element.next_element.css('div div')[1].css('b')[1].text

    year,month,day = sw_date_breakdown(date)
    
    departurezone = $timezone[departurecitycode]
    hour,min = time_convertion(departuretime, departurezone)

    arrivalzone = $timezone[arrivalcitycode]
    arrhour,arrmin = time_convertion(arrivaltimetext, arrivalzone)
    arrivaltime = Time.new(year,month,day,arrhour,arrmin)

    flytime = Time.new(year, month, day, hour, min)
    checkintime = get_checkin_time(flytime)

    puts "#{flytime} #{name} | #{confirmation} | #{date} | #{flightnumber} | #{departurecitycode} at #{departuretime} #{departurezone} | #{arrivalcitycode} at #{arrivaltime}  #{$timezone["#{arrivalcitycode}"]}"
    puts "pacific time departure: #{hour}:#{min}"
    
    puts "db create:"
    puts "firstname: #{firstname}, lastname: #{lastname}, confnum: #{confirmation},time: #{checkintime}"
    puts "departing_airport: #{departurecitycode}, depart_time: #{flytime}"
    puts "arriving_airport: #{arrivalcitycode}, arrive_time: #{arrivaltime}, flight_number: #{flightnumber}"

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
        conf_logged: Time.now})
    end
  end

  # find_conf_date = emailhtml.search "[text()*='Confirmation Date:']"
  # conf_date = find_conf_date.text.scan(/\d{2}\/\d{1,2}\/\d{4}/)[0]
  # confmonth,confday,confyear = date_breakdown(conf_date)

  # imap.copy(id, "logged")

  # imap.store(id, "+FLAGS", [:Deleted])
  puts "copied #{id} to logged and flagged for deletion"

  rescue => e
    puts "#{e.message} error. Move it to errors folder!"
    #move email to errors folder
    # imap.copy(id, "errors")
    # imap.store(id, "+FLAGS", [:Deleted])
    puts "copied #{id} to errors and flagged for deletion"
  end
end

imap.expunge