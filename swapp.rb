require 'sinatra'
require 'json'
require 'active_record'
require 'mysql'
require 'yaml'
require './checkinclass.rb'
require './logger'

$logger = Logger.new('swappweb.log')

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

get '/' do
  redirect '/index.html'
end

get '/index.html' do
  protected!
  send_file('private/index.html')
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
  returncheckins << "<td>Attempts</td><td>RespBoard</td><td>CheckedInTime</td><td>EmailedFrom</td></tr>"
  Checkindata.where(checkedin: true).order(:time).each do |x|
    returncheckins << "<tr>"
    returncheckins << "<td>#{x.firstname}</td>"
    returncheckins << "<td>#{x.lastname}</td>"
    returncheckins << "<td><a href='/allcheckins/sorted/#{x.resp_page_file}'>#{x.confnum}</a></td>"
    returncheckins << "<td>#{x.time.getlocal}</td>"
    returncheckins << "<td>#{x.checkedin}</td>"
    returncheckins << "<td>#{x.attempts}</td>"
    returncheckins << "<td>#{x.response_boarding}</td>"
    returncheckins << "<td>#{x.checkin_time}</td>"
    returncheckins << "<td>#{x.email_sender}</td>"
    returncheckins << "</tr>"
  end
  returncheckins << '</table>'
  return returncheckins
end

get '/allcheckins/sorted/:file' do
  protected!
  send_file("checkinpages/#{params[:file]}")
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
