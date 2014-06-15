require 'sinatra'
require 'restclient'
require 'nokogiri'
require 'json'
require 'active_record'
require 'sqlite3'

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
      return timeToCheckin < 5
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
          puts page.css('.passenger_name'). text
          puts page.css('td.boarding_group').text + page.css('td.boarding_position').text
          # page.css('img.group').each{|x| puts x['alt']}
          # page.css('img.position').each{|x| puts x['alt']}
          
          self.response_code = redirpage.code
          self.response_name = page.css('.passenger_name').text
          self.response_boarding = page.css('td.boarding_group').text + page.css('td.boarding_position').text
          self.checkin_time = Time.now
          
          self.resp_page_file = checkin_time.to_s.split[0..1].join + confnum + '.html'
          File.open(self.resp_page_file, 'w') { |file| file.write(redirpage.body) }
          
          self.save

          checkedin = true
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
  end
end

get '/' do
  redirect '/index.html'
end

get '/allcheckins' do
  returncheckins = ""
  Checkindata.all.each do |x|
    returncheckins << x.firstname << ' ' << x.lastname << '. Conf #: ' << x.confnum << ' at ' << x.time.to_s << "<br>"
  end
  return returncheckins
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

  # allcheckins << CheckinData.new(firstname, lastname, conf, time)
  newcheckin = Checkindata.create(firstname,lastname,conf,time)

  confirmhash = {firstname: newcheckin.firstname, lastname: newcheckin.lastname, confirmation: newcheckin.confnum, time: newcheckin.time.to_s}
  JSON.generate(confirmhash)
end
