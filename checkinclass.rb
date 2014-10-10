require 'time'

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
          self.checkin_time = Time.now.iso8601(3)
          
          self.resp_page_file = checkin_time.to_s.split[0..1].join('_') + '_' + confnum + '.html'
          File.open("checkinpages/#{self.resp_page_file}", 'w') { |file| file.write(redirpage.body) }
          
          self.checkedin = true

          self.save
          select_email_boarding_pass(self.email_sender, cookie)
          return true
        end
      end
    end
  end
end

def select_email_boarding_pass(email_address, cookie)
  emailform = { _optionPrint: 'on',
    optionEmail: 'true',
    _optionEmail: 'on',
    emailAddress: email_address,
    _optionText: 'on',
    book_now: 'Continue' }
  email_post = "http://www.southwest.com/flight/selectCheckinDocDelivery.html"
  get_boarding = RestClient.post(email_post,emailform,:cookies => cookie) { |response, request, result, &block| response }
end