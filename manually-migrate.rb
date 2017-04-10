require 'open-uri'
require 'uri'
require 'fileutils'
require 'nokogiri'
require 'optparse'


# Adds support for optional flags to the script
options = {
  :content_html_script => false
}

OptionParser.new do |opts|
  opts.banner = "Usage: manually-migrate.rb [options]"

  opts.on("-o", "--content-html-script", "Adds script to paste HTML inside content editor (default: false)") do |v|
    options[:content_html_script] = v
  end
end.parse!


print "Original url: "
original_url = STDIN.gets.strip

uri = URI::parse(original_url)

FileUtils::mkdir_p "./downloads#{uri.path}"

Dir.chdir "./downloads#{uri.path}"

current_folder = uri.path.split('/').last

html = open(original_url)
page = Nokogiri::HTML(html.read)
page.encoding = 'utf-8'

page_head_title = page.css("title")[0].text
page_head_description = page.at("meta[name=description]")

unless page_head_description == nil
  page_head_description = page_head_description['content']
else
  page_head_description = page.css("h2")[0].text
end

# Removes inline styles
page.xpath('@style|.//@style').remove

page_body_title = page.css("h1")[0].text
page_body_description = page.css("h2")[0].text
page_body_html = page.css('span#HTML_CONTENT')[0].to_s.gsub!(/[\n\r]+/, '')

inline_images = []

unless page_body_description == nil
  # Format Phone Numbers on Description
  page_body_description.gsub!(/(?:\d{1}\s)?\(?(\d{3})\)?-?\s?(\d{3})-?\s?(\d{4})/, '<strong><a href="tel:+1-\1-\2-\3">\1.\2.\3</a></strong>')

  # Exception regex for phone numbers already with dot format
  page_body_description.gsub!(/(?:\d{1}\s)?\(?(\d{3})\)\.(\d{3})\.(\d{4})/, '<strong><a href="tel:+1-\1-\2-\3">\1.\2.\3</a></strong>')
end

unless page_body_html == nil

  # Remove IDs
  page_body_html.gsub!(/id="?[^"\s]*"?/, '')

  # Remove <span> tags
  page_body_html.gsub!(/(<\/?span[^>]+>)/, '')

  # Validates HTML for unclosed tags
  page_body_html = Nokogiri::HTML::DocumentFragment.parse(page_body_html).to_s

  # Remove line breaks
  page_body_html.gsub!(/[\n\r]+/, '')

  # Find and save images
  images = page_body_html.scan(/<img.*?>/)
  unless images == nil
    images.each.with_index(1) do |image, index|
      src = image.match(/(?<=src=")[^"]+/).to_s

      if src.match(/https?:\/\//)
        image_url = src
      else
        image_url = "#{uri.scheme}://#{uri.host}#{src}"
      end

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
  page_body_html.gsub!(/<a href="(tel:|\d)[^>]+>(.+?)<\/a>/, '\2')

  # Format Phone Numbers
  page_body_html.gsub!(/(?:\d{1}\s)?\(?(\d{3})\)?-?\s?(\d{3})-?\s?(\d{4})/, '<strong><a href="tel:+1-\1-\2-\3">\1.\2.\3</a></strong>')

  # Exception regex for phone numbers already with dot format
  page_body_html.gsub!(/(?:\d{1}\s)?\(?(\d{3})\)\.(\d{3})\.(\d{4})/, '<strong><a href="tel:+1-\1-\2-\3">\1.\2.\3</a></strong>')

  # Remove Updated or Rev number
  page_body_html.gsub!(/\((Updated|Rev)\.? \d+\.?\)/, '')

  # Removes Duplicate strong tags
  page_body_html.gsub!(/<(strong)[^>]*>\s*?<\1[^>]*>(.*?)<\/\1>\s*?<\/\1>/, '<\1>\2</\1>')

  # Remove Empty tags that are not iframe
  page_body_html.gsub!(/<(?!iframe)([^>\s]+)([^>]+)?>([[:space:]]|&nbsp;|<[^>]+>)*<\/\1>/, '')

  # Wraps any block level text without tags on <p>
  page_body_html.gsub!(/(<\/(p|ul|h3)>)([^<]+?)(<(p|ul|h3)[^>]*>)/, '\1<p>\3</p>\4')

end

styles = "<style>"\
          ".manually-migrated ul { padding-left: 40px; } "\
          ".manually-migrated img { display:block; float: right; clear: right; margin: 0 0 20px 20px; } "\
          "@media (max-width: 750px) { .manually-migrated img { display:block; float: none; clear: both; margin: 20px auto; max-width: 100%; } } "\
          "</style>"

content_html = "#{styles} <div class='manually-migrated'><p>#{page_body_description}</p>#{page_body_html}</div>"

# Script used to open 'edit html' editor and paste content html inside of it
if options[:content_html_script]
  console_content_html_script = "jQuery(\"#Section_Content\").next().find(\".scContentButton:contains('Edit HTML')\").trigger('click'); "\
  "(function updateIframe() { "\
      "var $contentHtml = jQuery('#jqueryModalDialogsFrame').contents().find('#scContentIframeId0').contents().find('textarea'); "\
      "if($contentHtml.length < 1) { "\
          "setTimeout(updateIframe, 500); "\
      "} else { "\
        "$contentHtml.val('#{content_html.gsub(/'/, "\\\\'")}');"\
      "} "\
  "})();\n"
else
  console_content_html_script = ""
end

console_script = "jQuery(\".scEditorFieldLabel:contains('Title'), .scEditorFieldLabel:contains('Header')\").next().children('input').val('#{page_body_title.gsub(/'/, "\\\\'")}');\n"\
                "jQuery(\".scEditorFieldLabel:contains('PageHeadTitle:')\").next().children('input').val('#{page_head_title.gsub(/'/, "\\\\'")}');\n"\
                "jQuery(\".scEditorFieldLabel:contains('PageHeadDescription')\").next().children('input').val('#{page_head_description.gsub(/'/, "\\\\'")}');\n"\
                "jQuery(\".scEditorFieldLabel:contains('PageAddToSitemap')\").prev().children('input').prop('checked', true);\n"\
                "jQuery(\".scEditorFieldLabel:contains('PageShowInSearch')\").prev().children('input').prop('checked', true);\n"\
                "#{console_content_html_script}"

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
