# Copyright (c) 2005 Zed A. Shaw 
# You can redistribute it and/or modify it under the same terms as Ruby.
#
# Additional work donated by contributors.  See http://mongrel.rubyforge.org/attributions.html 
# for more information.

require 'test/test_helper'

$test_plugin_fired = 0

class TestPlugin < GemPlugin::Plugin "/handlers"
  include Mongrel::HttpHandlerPlugin

  def process(request, response)
    $test_plugin_fired += 1
  end
end


class Sentinel < GemPlugin::Plugin "/handlers"
  include Mongrel::HttpHandlerPlugin

  def process(request, response)
    raise "This Sentinel plugin shouldn't run."
  end
end


class ConfiguratorTest < Test::Unit::TestCase
  def setup
    @configurator_test_log = "configurator_test.log"
  end
  
  def teardown
    FileUtils.rm @configurator_test_log if File.exist? @configurator_test_log
  end
  
  ###
  
  def test_base_handler_config
    @port = process_based_port
    @config = nil

    redirect_test_io do
      @config = configurator do
        listener :port => process_based_port do
          # 2 in front should run, but the sentinel shouldn't since dirhandler processes the request
          uri "/", :handler => plugin("/handlers/testplugin")
          uri "/", :handler => plugin("/handlers/testplugin")
          uri "/", :handler => Mongrel::DirHandler.new(".")
          uri "/", :handler => plugin("/handlers/testplugin")

          uri "/test", :handler => plugin("/handlers/testplugin")
          uri "/test", :handler => plugin("/handlers/testplugin")
          uri "/test", :handler => Mongrel::DirHandler.new(".")
          uri "/test", :handler => plugin("/handlers/testplugin")

          debug "/"
          setup_signals

          run_config(HERE + "/mongrel.conf")
          load_mime_map(HERE + "/mime.yaml")

          run
        end
      end
    end
    
    # pp @config.listeners.values.first.classifier.routes

    @config.listeners.each do |host,listener| 
      assert listener.classifier.uris.length == 3, "Wrong number of registered URIs"
      assert listener.classifier.uris.include?("/"),  "/ not registered"
      assert listener.classifier.uris.include?("/test"), "/test not registered"
    end

    res = Net::HTTP.get(URI.parse("http://localhost:#{@port}/test"))
    assert res != nil, "Didn't get a response"
    assert $test_plugin_fired == 3, "Test filter plugin didn't run 3 times."

    redirect_test_io do
      res = Net::HTTP.get(URI.parse("http://localhost:#{@port}/"))

      assert res != nil, "Didn't get a response"
      assert $test_plugin_fired == 6, "Test filter plugin didn't run 6 times."
    end

    redirect_test_io do
      @config.stop(false, true)
    end

    assert_raise Errno::EBADF, Errno::ECONNREFUSED do
      res = Net::HTTP.get(URI.parse("http://localhost:#{@port}/"))
    end
  end
  
  def test_logger
    logger  = Logger.new(@configurator_test_log)
    message = "You want it to be one way. But it's the other way."
    
    redirect_test_io do
      @config = configurator do
        self.logger = logger
        log message
      end
    end
    
    assert_equal logger, @config.logger
    assert File.exist?(@configurator_test_log), "logger file not created"
    assert File.read(@configurator_test_log).include?(message), "message not logged"
  end
  
  ###
  
  def configurator(options = {}, &block)
    options[:host] ||= "localhost"
    Mongrel::Configurator.new options, &block
  end
end
