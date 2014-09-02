require 'rest_client'
require 'nokogiri'
require 'csv'

sw_dest = "http://en.wikipedia.org/wiki/Southwest_Airlines_destinations"
response = RestClient.get(sw_dest) { |response, request, result, &block| response }
homehtml = Nokogiri::HTML(response.body)

homehtml.css('table')[1].css('tr').first.remove

airport_hash = {}

homehtml.css('table')[1].css('tr').each do |row|
  airport_hash[row.css('td')[2].text.strip] = row.css('td').first.text.strip
end

# airports.dat csv file comes from http://openflights.org/data.html
CSV.foreach('airports.dat') do |data|
  if airport_hash.keys.include?(data[4])
    airport_hash[data[4]] = data[9]
  end
end

File.open('airporthash.rb','w') { |f| f.write(airport_hash) }