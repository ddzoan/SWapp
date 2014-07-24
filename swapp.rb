require 'sinatra'
require 'rest_client'
require 'nokogiri'
require 'json'
require 'active_record'
# require 'sinatra-activerecord'

# set :database, 'checkins.db'
def dbconnect()
  ActiveRecord::Base.establish_connection(
    :adapter => "sqlite3",
    :database => "checkins.db"
  )
end

dbconnect()

def resetdbconnection()
  ActiveRecord::Base.clear_active_connections!

  dbconnect()
end

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
    end
  end
end

class Checkindata < ActiveRecord::Base
  def timeToCheckin()
    time - Time.now
  end

  def tryToCheckin?()
    if checkedin
      return false
    elsif attempts > 50
      return false
    else
      return timeToCheckin < 2
    end
  end

  def flight_checkin()
    self.increment!(:attempts)
    form = { :'previously-selected-bar-panel' => "check-in-panel",
    :confirmationNumber => confnum,
    :firstName => firstname,
    :lastName => lastname,
    :submitButton => "Check In" }

    checkin_doc = "http://www.southwest.com/flight/retrieveCheckinDoc.html"

    response = RestClient.post(checkin_doc,form) { |response, request, result, &block| response }

    cookie = response.cookies

    if response.code == 200
      page = Nokogiri::HTML(response.body)
      if page.css("div#error_wrapper").length == 1
        puts "GOT ERROR DIV, WRITING ERROR TO FILE"
        File.open(Time.now.to_s.split[0..1].join + '_errordiv.html', 'w') { |file| file.write(page.css("div#error_wrapper").text) }
      else
        puts "got 200, should have gotten 302, writing page to file"
        File.open(Time.now.to_s.split[0..1].join + '_bad200.html', 'w') { |file| file.write(page) }
      end

      return false
    elsif response.code == 302
      # puts "forwarded to: #{response.headers[:location]}"

      #follow forward
      response = RestClient.get(response.headers[:location],:cookies => cookie) { |response, request, result, &block| response }
      page = Nokogiri::HTML(response.body)
      
      if page.css("input.swa_buttons_submitButton")[0]['title'] == "Check In"
        real_checkin = "http://www.southwest.com/flight/selectPrintDocument.html"
        checkin_form = { :'checkinPassengers[0].selected' => true, :printDocuments => "Check In" }

        final_response = RestClient.post(real_checkin,checkin_form,:cookies => cookie) { |response, request, result, &block| response }
        if final_response.code == 302
          redir = final_response.headers[:location]
          redirpage = RestClient.get(redir,:cookies => cookie) { |response, request, result, &block| response }
          # puts redirpage.code
          # puts redirpage.body
          puts "Should be SUCCESS at #{Time.now}"
          page = Nokogiri::HTML(redirpage.body)
          puts page.css('.passenger_name').text.strip.split.join(' ')
          puts page.css('td.boarding_group').text + page.css('td.boarding_position').text
          # page.css('img.group').each{|x| puts x['alt']}
          # page.css('img.position').each{|x| puts x['alt']}
          
          self.response_code = redirpage.code
          self.response_name = page.css('.passenger_name').text.strip.split.join(' ')
          self.response_boarding = page.css('td.boarding_group').text + page.css('td.boarding_position').text
          self.checkin_time = Time.now
          
          self.resp_page_file = checkin_time.to_s.split[0..1].join('_') + '_' + confnum + '.html'
          File.open("checkinpages/#{self.resp_page_file}", 'w') { |file| file.write(redirpage.body) }
          
          self.checkedin = true

          self.save
          return true
        end
      end
    end
  end
end

allcheckins = []

Thread.new do # work thread
  while true do
    Checkindata.where(checkedin: false).order(:time).each do |checkindata|
      if checkindata.tryToCheckin?
        checkindata.flight_checkin
      end
    end
    resetdbconnection()
  end
end

get '/' do
  redirect '/index.html'
end

get '/allcheckins' do
  returncheckins = "<table><tr><td>First Name</td><td>Last Name</td><td>Conf #</td><td>Checkin Time</td><td>Checked in?</td></tr>"
  Checkindata.all.each do |x|
    returncheckins << "<tr><td>#{x.firstname}</td>"
    returncheckins << "<td>#{x.lastname}</td>"
    returncheckins << "<td>#{x.confnum}</td>"
    returncheckins << "<td>#{x.time.to_s}</td>"
    returncheckins << "<td>#{x.checkedin}</td></tr>"
    # add delete link later
    # returncheckins << "<tr><td><a href="">X</a></td><td>#{x.firstname}</td><td>#{x.lastname}</td><td>#{x.confnum}</td><td>#{x.time.to_s}</td></tr>"
  end
  returncheckins << '</table>'
  return returncheckins
end

get '/allcheckins/sorted' do
  returncheckins = "<table><td>First Name</td><td>Last Name</td><td>Conf #</td><td>Checkin Time</td><td>Checked In?</td>"
  returncheckins << "<td>Attempts</td><td>RespCode</td><td>File</td><td>RespName</td><td>RespBoard</td><td>CheckedInTime</td></tr>"
  Checkindata.where(checkedin: false).order(:time).each do |x|
    returncheckins << "<tr>"
    returncheckins << "<td>#{x.firstname}</td>"
    returncheckins << "<td>#{x.lastname}</td>"
    returncheckins << "<td>#{x.confnum}</td>"
    returncheckins << "<td>#{x.time.to_s}</td>"
    returncheckins << "<td>#{x.checkedin}</td>"
    returncheckins << "<td>#{x.attempts}</td>"
    returncheckins << "<td>#{x.response_code}</td>"
    returncheckins << "<td>#{x.resp_page_file}</td>"
    returncheckins << "<td>#{x.response_name}</td>"
    returncheckins << "<td>#{x.response_boarding}</td>"
    returncheckins << "<td>#{x.checkin_time}</td>"
    returncheckins << "</tr>"
  end
  returncheckins << '</table>'

  returncheckins << '<br><br>'
  returncheckins << "<table><td>First Name</td><td>Last Name</td><td>Conf #</td><td>Checkin Time</td><td>Checked In?</td>"
  returncheckins << "<td>Attempts</td><td>RespCode</td><td>File</td><td>RespName</td><td>RespBoard</td><td>CheckedInTime</td></tr>"
  Checkindata.where(checkedin: true).order(:time).each do |x|
    returncheckins << "<tr>"
    returncheckins << "<td>#{x.firstname}</td>"
    returncheckins << "<td>#{x.lastname}</td>"
    returncheckins << "<td>#{x.confnum}</td>"
    returncheckins << "<td>#{x.time.to_s}</td>"
    returncheckins << "<td>#{x.checkedin}</td>"
    returncheckins << "<td>#{x.attempts}</td>"
    returncheckins << "<td>#{x.response_code}</td>"
    returncheckins << "<td>#{x.resp_page_file}</td>"
    returncheckins << "<td>#{x.response_name}</td>"
    returncheckins << "<td>#{x.response_boarding}</td>"
    returncheckins << "<td>#{x.checkin_time}</td>"
    returncheckins << "</tr>"
  end
  returncheckins << '</table>'
  return returncheckins
end

get '/resetdbconnection' do
  resetdbconnection()
end

post '/newcheckin' do
  firstname = params[:first]
  lastname = params[:last]
  conf = params[:conf]
  hour = params[:hour]
  minute = params[:min]
  month = params[:month]
  day = params[:day]
  year = params[:year]

  time = Time.new(year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i)

  newcheckin = Checkindata.create({firstname: firstname, lastname: lastname, confnum: conf,time: time})

  confirmhash = {firstname: newcheckin.firstname, lastname: newcheckin.lastname, confirmation: newcheckin.confnum, time: newcheckin.time.to_s}
  JSON.generate(confirmhash)
end
