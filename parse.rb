# encoding: utf-8

require 'rubygems'
require 'nokogiri'
require 'csv'
require 'iconv'

def clean_number(s)
  s.delete('.').gsub(',','.')
end

# Always some encoding black magic needed :/ I think the source is wrong (or I screwed up)
def to_UTF8(s)
  Iconv.iconv("iso-8859-1", "utf-8", s).first.force_encoding('UTF-8')
end

# Unfortunately the region ID in the Ministry of Finance site is not the same
# as the region ID in the INE site (where we get population from). The latter
# seems more 'official', so we're using that.
# Note: there are a couple of different spellings per region in the source data,
# plus case variations, so be aware of that.
def get_INE_code(region)
  name_to_INE_map = {
    'comunidad autónoma de andalucía' => 1,
    'comunidad autónoma de aragón' => 2,
    'comunidad autónoma del principado de asturias' => 3,
    'comunitat valenciana' => 10,
    'comunidad autónoma de canarias' => 5,
    'comunidad autónoma de cantabria' => 6,
    'comunidad autónoma de castilla y león' => 7,
    'comunidad de castilla y león' => 7,
    'comunidad autónoma de castilla-la mancha' => 8,
    'comunidad autónoma de cataluña' => 9,
    'ciudad autónoma de ceuta' => 18,
    'comunidad autónoma de extremadura' => 11,
    'comunidad autónoma de galicia' => 12,
    'comunidad autónoma de las illes balears' => 4,
    'comunidad autónoma de madrid' => 13,
    'comunidad de madrid' => 13,
    'ciudad autónoma de melilla' => 19,
    'comunidad autónoma de la región de murcia' => 14,
    'comunidad foral de navarra' => 15,
    'comunidad autónoma del país vasco' => 16,
    'comunidad autónoma de la rioja' => 17
  }
  return name_to_INE_map[to_UTF8(region.downcase)] || "ERROR: #{region}"
end

def parse_file(filename)
  doc = Nokogiri::HTML(open(filename, "r:ISO-8859-1"))
  
  # I thought the CA name was a good key, but turns out it changes sligthly
  # with time. So we'll use the original id instead, part of the filename
  filename =~ /\/(\d\d)\./
  region_id = $1
  
  # First, get the metadata about the file from the first chunk of text
  title = doc.css('h1')[0]
  return if title.nil? # Some error pages
  title.text.strip =~ /EJERCICIO +(\d\d\d\d)/
  year = $1

  region_name = doc.css('h3')[0].text.strip
  
  # ...make sure it's fine...
  if year.nil? or year.empty? or region_name.nil? or region_name.empty?
    $stderr.puts "ERROR: can't read metadata for file [#{filename}]"
    return
  end

  # ...and then, process all the rows...
  doc.css('tr').each do |r|
    # ...but look only at the ones with the data
    columns = r.css('td')
    next if columns.size!=12
  
    # ...and ignore the subtotal rows
    policy_id = columns.shift.text
    policy_label = to_UTF8(columns.shift.text)
  
    # Extract the values from remaining columns
    values = columns.map {|c| clean_number(c.text.strip)}
  
    # And output. Note: at the moment we just care about what gets shown in the DVMI region 
    # visualization, so we ignore a bunch of stuff. We display only:
    #  - the total expense, even if we have the chapter breakdown. 
    #  - region id is enough, name not needed.
    #  - only for years after (and including) 2006
    #  - only for actual regions, ignore the total
    #  - only non-zero chapter-level data, ignore 'expense area' subtotals
    if year.to_i >= 2006 and region_id != '00' and policy_id =~ /\d\d/ and !values.last.empty?
      region_INE_code = get_INE_code(region_name)
      puts CSV::generate_line([year, region_INE_code, policy_id, policy_label, values.last])
    end
  end
end

# puts CSV::generate_line(['year', 'region_id', 'policy_id', 'policy_label', 'total'])
puts 'Ano,Idcomu,Codigo,Funcion,Total'  # Header expected by Javascript in DVMI

# Parse all files in the staging folder
Dir['staging/*txt'].each {|filename| parse_file(filename)}