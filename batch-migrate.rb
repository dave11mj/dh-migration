require 'selenium-webdriver'
require 'optparse'
require 'json'
require 'yaml'

@options = {
  :save => false
}

OptionParser.new do |opts|
  opts.banner = "Usage: manually-migrate.rb [options]"

  opts.on("-s", "--save [true]", TrueClass, "Auto saves URLs batch (default: false)") do |v|
    @options[:save] = v.to_s.downcase == 'true' || v.to_s.downcase == ''
  end

end.parse!

# Configurations used by the batch script
@configs = YAML.load_file('config-batch-migrate.yml')

# Browser that will be used by Selenium
@browser = Selenium::WebDriver.for :chrome
@old_url_browser = Selenium::WebDriver.for :chrome

# Makes Selenium browsers focus and maximized
@old_url_browser.switch_to.window @old_url_browser.window_handle
@old_url_browser.manage.window.maximize

@browser.switch_to.window @browser.window_handle
@browser.manage.window.maximize

# Seems to be used to delay Selenium / wait until action happens
@wait = Selenium::WebDriver::Wait.new(:timeout => 10)

@logged_in = false

def login
  # Waits until username field exists and enter it
  username = @wait.until {
    element = @browser.find_element(:id, "UserName")
    element if element.displayed?
  }
  username.send_keys(@configs['login']['username'])

  # Waits until password field to exists and enter it
  password = @wait.until {
    element = @browser.find_element(:id, "Password")
    element if element.displayed?
  }
  password.send_keys(@configs['login']['password'])

  # Waits until submit button to exists and click it
  submit = @wait.until {
    element = @browser.find_element(:name, "ctl08")
    element if element.displayed?
  }
  submit.click

  @logged_in = true
end

# Iterate through the pages and input their content
@configs['pages'].each.with_index do |config_page, index|
  old_url = config_page.split(/[[:space:]]+/)[0]
  new_url = config_page.split(/[[:space:]]+/)[1]

  unless new_url
    puts "InvalidEntryError: Entry ##{index+1} format should be [old url]/(\\s|\\t)+/[new url]"
    next
  end

  page = JSON.parse(`ruby manually-migrate.rb -u #{old_url} -n #{new_url} -j -o`)

  # Make sure the page is not a 404 and skip if it is
  begin

    if index == 0
      # Navigate to Login page
      @browser.navigate.to page['edit_page_url']
    else
      # open a new tab and set the context
      @browser.execute_script "window.open('_blank', 'tab#{index}')"
      @browser.switch_to.window "tab#{index}"
      @browser.get page['edit_page_url']
    end

    # Login if the user is not logged
    unless @logged_in
      login
    end

    # Waits until main nav exists
    main_nav = @wait.until {
      element = @browser.find_element(:id, "main-nav")
      element if element.displayed?
    }

    # Excute jQuery script from manually-migrate.rb
    @browser.execute_script(page['console_script'])

    if @options[:save] == true
      # Wait for modal iframe to open and switch to it
      jqueryModalDialogsFrame = @wait.until {
        element = @browser.find_element(:id, "jqueryModalDialogsFrame")
        element if element.displayed?
      }
      @browser.switch_to.frame(jqueryModalDialogsFrame)

      # Wait for HTML Editor Iframe to Open and switch to it
      scContentIframeId0 = @wait.until {
        element = @browser.find_element(:id, "scContentIframeId0")
        element if element.displayed?
      }
      @browser.switch_to.frame(scContentIframeId0)

      # Wait until accept button is visible and click it
      accept_button = @wait.until {
          element = @browser.find_element(:id, "OK")
          element if element.displayed?
      }
      accept_button.click

      # switch back to the main document
      @browser.switch_to.default_content

      # Find form iframe and switch to it
      scPageExtendersFormIframe = @browser.find_element(:xpath, "//form[@id = 'scPageExtendersForm']//iframe")
      @browser.switch_to.frame(scPageExtendersFormIframe)

      # Find Save/Close button and click it
      saveAndCloseButton = @browser.find_element(:xpath, "//a[@title = 'Save Changes and Close the window.']")
      saveAndCloseButton.click

      # switch back to the main document
      @browser.switch_to.default_content

      # Hide Main Navigation
      @browser.execute_script('jQuery("#main-nav").css("visibility", "hidden")')
    end

    # Open a window with old URL for reference
    if index == 0
      # Navigate to Login page
      @old_url_browser.navigate.to old_url
    else
      # open a new tab and set the context
      @old_url_browser.execute_script "window.open('_blank', 'old_url_tab#{index}')"
      @old_url_browser.switch_to.window "old_url_tab#{index}"
      @old_url_browser.get old_url
    end


  rescue Selenium::WebDriver::Error::TimeOutError
    puts "TimeOutError: #{page['edit_page_url']}"
    next
  end

end


puts "Press [Enter] to stop the script."
puts "Note: Any unsaved progress will be lost"
response = gets("\n").chomp
