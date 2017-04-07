require 'open-uri'
require 'uri'
require 'fileutils'
require 'nokogiri'

print "Original url: "
original_url = gets.strip

uri = URI::parse(original_url)

FileUtils::mkdir_p "./downloads#{uri.path}"

Dir.chdir "./downloads#{uri.path}"

current_folder = uri.path.split('/').last

page = Nokogiri::HTML(open(original_url))

page_head_title = page.css("title")[0].text
page_head_description = page.at("meta[name=description]")

unless page_head_description == nil
  page_head_description = page_head_description['content']
else
  page_head_description = page.css("h2")[0].text
end

page_body_title = page.css("h1")[0].text
page_body_description = page.css("h2")[0].text
page_body_html = page.css('span#HTML_CONTENT')[0].to_s.gsub!(/\n/, '')

inline_images = []

unless page_body_html == nil

  # Removes wrapping HTML_CONTENT span tags
  page_body_html.gsub!(/(<span id="?HTML_CONTENT[^>]+>|<\/span>$)/, '')

  # Remove IDs
  page_body_html.gsub!(/id="?[^"\s]*"?/, '')

  # Remove <br> tags
  # page_body_html.gsub!(/<br\/?>/, '')

  # Validates HTML for unclosed tags
  page_body_html = Nokogiri::HTML::DocumentFragment.parse(page_body_html).to_s

  # Remove line breaks
  page_body_html.gsub!(/\n/, '')

  # Find and save images
  images = page_body_html.scan(/<img.*?>/)
  unless images == nil
    images.each.with_index(1) do |image, index|
      src = image.match(/(?<=src=")[^"]+/)
      image_url = "#{uri.scheme}://#{uri.host}#{src}"

      inline_images << "file: inline-#{current_folder}-photo-#{index}.jpg — alt: #{(image.match(/(?<=alt=")[^"]+/) || 'none')}\n"

      open(image_url) do |f|
       File.open("inline-#{current_folder}-photo-#{index}.jpg","wb") do |file|
         file.puts f.read
       end
      end
    end
  end

  # Replace h1 and h2 with h3
  page_body_html.gsub!(/<(\/?)h[12][^>]*>/, '<\1h3>')

  # Remove Image tags
  page_body_html.gsub!(/<img.*?>/, '')

  # Remove Tel Links
  page_body_html.gsub!(/<a href="tel:[^>]+>(.+?)<\/a>/, '\1')

  # Format Phone Numbers
  page_body_html.gsub!(/(?:\d{1}\s)?\(?(\d{3})\)?(-|\.)?\s?(\d{3})(-|\.)?\s?(\d{4})/, '<strong><a href="tel:+1-\1-\3-\5">\1.\3.\5</a></strong>')

  # Remove Updated or Rev number
  page_body_html.gsub!(/\((Updated|Rev)\.? \d+\.?\)/, '')

  # Removes Duplicate strong tags
  page_body_html.gsub!(/<(strong)[^>]*>\s*?<\1[^>]*>(.*?)<\/\1>\s*?<\/\1>/, '<\1>\2</\1>')

  # Remove Empty tags that are not iframe
  page_body_html.gsub!(/<(?!iframe)([^>\s]+)([^>]+)?>[[:space:]]*<\/\1>/, '')

  # Remove Empty tags that were nested inside empty tags
  # Note: if there was a 3rd lv of nested empty tags I give up ...
  page_body_html.gsub!(/<(?!iframe)([^>\s]+)([^>]+)?>[[:space:]]*<\/\1>/, '')

end

content_html = "<style>.manually-migrated ul { padding-left: 40px; } .manually-migrated img { display:block; float: right; clear: right; margin: 0 0 20px 20px; }</style><div class='manually-migrated'><p>#{page_body_description}</p>#{page_body_html}</div>"

console_script = "jQuery(\".scEditorFieldLabel:contains('Title'), .scEditorFieldLabel:contains('Header')\").next().children('input').val('#{page_body_title.gsub(/'/, "\\\\'")}');\n"\
                "jQuery(\".scEditorFieldLabel:contains('PageHeadTitle:')\").next().children('input').val('#{page_head_title.gsub(/'/, "\\\\'")}');\n"\
                "jQuery(\".scEditorFieldLabel:contains('PageHeadDescription')\").next().children('input').val('#{page_head_description.gsub(/'/, "\\\\'")}');\n"\
                "jQuery(\".scEditorFieldLabel:contains('PageAddToSitemap')\").prev().children('input').prop('checked', true);\n"\
                "jQuery(\".scEditorFieldLabel:contains('PageShowInSearch')\").prev().children('input').prop('checked', true);\n"

notes = "###Original URL\n"\
        "#{original_url}\n\n"\
        "###PageHeadTitle\n"\
        "#{page_head_title}\n\n"\
        "###PageHeadDescription\n"\
        "#{page_head_description}\n\n"\
        "###Content Title\n"\
        "#{page_body_title}\n\n"\
        "###Content HTML\n"\
        "#{content_html}\n\n"\
        "###Inline Images\n"\
        "#{inline_images.join('')}\n"\
        "###Console Script\n"\
        "#{console_script}"

puts "\n#{notes}\n"

File.open("notes.md", 'w') { |file| file.write(notes) }

# Copies to clipboard on Macs
def pbcopy(input)
  str = input.to_s
  IO.popen('pbcopy', 'w') { |f| f << str }
  str
end

begin
  pbcopy(console_script)
  puts "Copied Console Script to clipboard\n\n"
rescue
  puts "Done\n\n"
end
