require 'nokogiri'
require 'set'

# use global var $timezone["AAA"] to get time zone, replace AAA with airport code
require './airportdata/airporthash.rb'

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

  class TestError < Error
    def initialize(message = "TEST ERROR")
      super(message)
    end
  end
end

def email_parser(emailbody, sender)
  checkin_hashes = []

  emailhtml = Nokogiri::HTML(emailbody)
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

    # name = find_name[0].parent.parent.parent.parent.parent.next_element.css('div').last.text.strip
    name = find_name[0].parent.parent.parent.parent.parent.next_element.css('div').last.text.strip
    names = [name_conversion(name)]
  else
    confirmation = find_conf[0].last_element_child.child.text.strip

    passenger_header_element = find_name[0].parent.parent.parent.parent.parent
    names = get_passenger_names(passenger_header_element)
  end

  if find_conf.empty?
    raise EmailScrape::ConfirmationError
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
      
      # if no other bold item in this text found, that means there is another leg of flight
      # the code in the else block traverses to the next table with the next leg data
      if !departure_elements.css('div')[0].css('b')[2].nil?
        arrivalcity = departure_elements.css('div')[0].css('b')[2].text
        arrivalcitycode = departure_elements.css('div')[0].text.scan(/\((\w{3})\)/).last.first
        arrivaltimetext = departure_elements.css('div')[0].css('b')[3].text
      else
        next_table_element = departure_elements.parent.parent.parent.next_element
        arrivalcity = next_table_element.css('td')[3].css('b')[0].text
        arrivalcitycode = next_table_element.css('td')[3].text.scan(/\((\w{3})\)/).last.first
        arrivaltimetext = next_table_element.css('td')[3].css('b')[1].text
      end

      year,month,day = sw_date_breakdown(date)
      
      departurezone = $timezone[departurecitycode]
      hour,min = time_convertion(departuretime, departurezone)

      arrivalzone = $timezone[arrivalcitycode]
      arrhour,arrmin = time_convertion(arrivaltimetext, arrivalzone)
      arrivaltime = Time.new(year,month,day,arrhour,arrmin)

      flytime = Time.new(year, month, day, hour, min)
      checkintime = get_checkin_time(flytime)

      names.each do |name|
        if $debug
          puts "#{flytime} #{name} | #{confirmation} | #{date} | #{flightnumber} | #{departurecitycode} at #{departuretime} #{departurezone} | #{arrivalcitycode} at #{arrivaltime}  #{$timezone["#{arrivalcitycode}"]}"
          puts "pacific time departure: #{hour}:#{min}"
          
          puts "db create:"
          puts "firstname: #{name[0]}, lastname: #{name[1]}, confnum: #{confirmation},time: #{checkintime}"
          puts "departing_airport: #{departurecitycode}, depart_time: #{flytime}"
          puts "arriving_airport: #{arrivalcitycode}, arrive_time: #{arrivaltime}, flight_number: #{flightnumber}"
        end

        checkin_hashes << {firstname: name[0],
          lastname: name[1],
          confnum: confirmation,
          time: checkintime,
          departing_airport: departurecitycode,
          depart_time: flytime,
          arriving_airport: arrivalcitycode,
          arrive_time: arrivaltime,
          flight_number: flightnumber,
          email_sender: sender,
          conf_logged: Time.now}
      end
    end
  end

  return [confirmation, checkin_hashes]
end

def get_passenger_names(header_element)
  passengers = 0
  names = []
  passenger_element = header_element.next_element

  # deal with old email format
  if passenger_element.css('td').length == 1
    name = passenger_element.css('div').first.text.strip
    firstname, lastname = name_conversion(name)
    names << [firstname,lastname]
  end

  while passenger_element.css('td').length == 5
    passengers += 1
    name = passenger_element.css('div').first.text.strip
    firstname, lastname = name_conversion(name)
    names << [firstname,lastname]
    passenger_element = passenger_element.next_element.next_element
  end
  return names
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
    raise EmailScrape::DateError.new("The month and date does not occur this year or next year")
  end

  return [year, month, day]
end

def time_convertion(time, offset)
  hour = time.split(':')[0].to_i
  min = time.split(' ')[0].split(':').last.to_i
  ampm = time.split(' ').last

  hour = hour + 12 if ampm == "PM" && hour < 12

  hour = hour + $timezone['SFO'].to_i - offset.to_i

  return [hour,min]
end