require 'sinatra'
require 'restclient'
require 'nokogiri'
require 'json'

class CheckinData
  attr_accessor :firstname, :lastname, :confnum, :time, :checkedin, :attempts

  def initialize(firstname,lastname,confnum,time)
    @firstname = firstname
    @lastname = lastname
    @confnum = confnum
    @time = time
    @checkedin = false
    @attempts = 0
  end

  def timeToCheckin()
    time - Time.now
  end

  def tryToCheckin?()
    if @checkedin
      return false
    elsif attempts > 50
      return false
    else
      puts time + ' - ' + Time.now + ' = ' + (time - Time.now)
      return (time - Time.now) < 5
    end
  end

  def flight_checkin()
    @attempts += 1
    form = { :'previously-selected-bar-panel' => "check-in-panel",
    :confirmationNumber => @confnum,
    :firstName => @firstname,
    :lastName => @lastname,
    :submitButton => "Check In" }
    
    checkin_doc = "http://www.southwest.com/flight/retrieveCheckinDoc.html"

    response = RestClient.post(checkin_doc,form) { |response, request, result, &block| response }

    cookie = response.cookies

    if response.code == 200
      page = Nokogiri::HTML(response.body)
      if page.css("div#error_wrapper").length == 1
        puts "GOT ERROR DIV, PROBABLY NOT TIME TO CHECK IN YET"
        return false
      end
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
          puts redirpage.code
          puts redirpage.body
          puts "Should be SUCCESS at #{Time.now}"
          page = Nokogiri::HTML(redirpage.body)
          puts page.css('.passenger_name').text
          puts page.css('td.boarding_group').text + page.css('td.boarding_position').text
          # page.css('img.group').each{|x| puts x['alt']}
          # page.css('img.position').each{|x| puts x['alt']}
          checkedin = true
          return true
        end
      end
    end
  end
end

allcheckins = []

Thread.new do # trivial example work thread
  while true do
    sleep 1
    allcheckins.each do |checkindata|
      if checkindata.tryToCheckin?
        checkindata.flight_checkin
      end
    end
  end
end

get '/' do
  redirect '/index.html'
end

get '/checkin' do
	firstname = params[:first]
  lastname = params[:last]
  conf = params[:conf]
  time = Time.at(params[:time].to_i)

  allcheckins << CheckinData.new(firstname,lastname,conf,time)

  allcheckins.to_s
end

get '/allcheckins' do
  returnshit = ""
  allcheckins.each do |x|
    returnshit << x.firstname << ' ' << x.lastname << '. Conf #: ' << x.confnum << ' at ' << x.time.to_s << "<br>"
  end
  return returnshit
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

  allcheckins << CheckinData.new(firstname, lastname, conf, time)

  confirmhash = {firstname: firstname, lastname: lastname, confirmation: conf, time: time.to_s}
  JSON.generate(confirmhash)
end