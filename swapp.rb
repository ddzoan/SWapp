require 'sinatra'
require 'rest_client'
require 'nokogiri'
require 'json'
require 'active_record'
require 'mysql'
require 'yaml'

dbconfig = YAML::load(File.open('database.yml'))
ActiveRecord::Base.establish_connection(dbconfig)

helpers do
  def protected!
    return if authorized?
    headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
    halt 401, "Not authorized\n"
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? and @auth.basic? and @auth.credentials and @auth.credentials == ['guest', ARGV.last]
  end
end

def resetdbconnection()
  ActiveRecord::Base.clear_active_connections!
end

after do
  ActiveRecord::Base.clear_active_connections!
end

class Checkindata < ActiveRecord::Base
  def timeToCheckin()
    time - Time.now
  end

  def tryToCheckin?()
    if checkedin
      return false
    elsif attempts > 10
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
        File.open("errors/#{Time.now.to_s.split[0..1].join}_" + confnum + '_errordiv.html', 'w') { |file| file.write(page.css("div#error_wrapper").text) }
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
          puts "Should be SUCCESS at #{Time.now}"
          page = Nokogiri::HTML(redirpage.body)
          puts page.css('.passenger_name').text.strip.split.join(' ')
          puts page.css('td.boarding_group').text + page.css('td.boarding_position').text
          
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
    ActiveRecord::Base.connection_pool.with_connection do
      Checkindata.where(checkedin: false).order(:time).each do |checkindata|
        if checkindata.tryToCheckin?
          checkindata.flight_checkin
        end
      end
    end
  end
end

get '/' do
  redirect '/index.html'
end

get '/allcheckins' do
  protected!
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
  protected!
  returncheckins = "<table><td>First Name</td><td>Last Name</td><td>Conf #</td><td>Checkin Time</td><td>Checked In?</td>"
  returncheckins << "<td>Attempts</td>"
  returncheckins << "<td>Depart</td><td>Arrive</td><td>Flight#</td><td>LoggedDate</td><td>EmailedFrom</td>"
  Checkindata.where(checkedin: false).order(:time).each do |x|
    returncheckins << "<tr>"
    returncheckins << "<td>#{x.firstname}</td>"
    returncheckins << "<td>#{x.lastname}</td>"
    returncheckins << "<td>#{x.confnum}</td>"
    returncheckins << "<td>#{x.time.getlocal}</td>"
    returncheckins << "<td>#{x.checkedin}</td>"
    returncheckins << "<td>#{x.attempts}</td>"
    returncheckins << "<td>#{x.departing_airport}</td>"
    returncheckins << "<td>#{x.arriving_airport}</td>"
    returncheckins << "<td>#{x.flight_number}</td>"
    returncheckins << "<td>#{x.conf_logged}</td>"
    returncheckins << "<td>#{x.email_sender}</td>"
    returncheckins << "</tr>"
  end
  returncheckins << '</table>'

  returncheckins << '<br><br>'
  returncheckins << "<table><td>First Name</td><td>Last Name</td><td>Conf #</td><td>Checkin Time</td><td>Checked In?</td>"
  returncheckins << "<td>Attempts</td><td>RespCode</td><td>RespName</td><td>RespBoard</td><td>CheckedInTime</td><td>EmailedFrom</td></tr>"
  Checkindata.where(checkedin: true).order(:time).each do |x|
    returncheckins << "<tr>"
    returncheckins << "<td>#{x.firstname}</td>"
    returncheckins << "<td>#{x.lastname}</td>"
    returncheckins << "<td>#{x.confnum}</td>"
    returncheckins << "<td>#{x.time.to_s}</td>"
    returncheckins << "<td>#{x.checkedin}</td>"
    returncheckins << "<td>#{x.attempts}</td>"
    returncheckins << "<td>#{x.response_code}</td>"
    returncheckins << "<td>#{x.response_name}</td>"
    returncheckins << "<td>#{x.response_boarding}</td>"
    returncheckins << "<td>#{x.checkin_time}</td>"
    returncheckins << "<td>#{x.email_sender}</td>"
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
