require 'uri'
require 'net/http'

require_relative 'utils/zip_file_generator'

module DrupalAws
  module Tasks
    class Status

      def initialize
        @options = {}
        @data_dir = File.expand_path(File.dirname(__FILE__) + '/../../../data')
      end

      def run
        option_parser.parse!
        help if @options[:help]

        # Force the N. Virgina region.
        AWS.config(region: 'us-east-1')

        # Create AWS objects to work with.
        cfm = AWS::CloudFormation.new
        ec2 = AWS::EC2.new

        # Loop through looking for the "drupal" stack.
        puts 'Looking for a Drupal stack.' if @options[:verbose]
        stack = cfm.stacks.detect { |stack| /drupal-WebServer/.match(stack.name) }

        if stack.nil? or !stack.exists?
          puts 'The Drupal stack could not be found.'
          exit 1
        end

        puts "Found a Drupal stack named '#{stack.name}'" if @options[:verbose]

        puts 'Looking for a web server in the stack.' if @options[:verbose]
        resource = stack.resources.detect do |resource|
          resource.logical_resource_id == 'PuppetClient'
        end

        if resource.nil?
          puts 'No web server could be found in the stack.'
          exit 1
        end

        puts "Found a web server with id '#{resource.physical_resource_id}'" if @options[:verbose]

        web_server = ec2.instances[resource.physical_resource_id]
        host = web_server.dns_name

        puts "Checking for a running Drupal instance at http://#{host}/" if @options[:verbose]

        uri = URI.parse("http://#{host}/")
        res = Net::HTTP.get_response(uri)
        if res.code == '200' && /<body.*?>/ =~ res.body
          puts 'The site is up.'
          exit 0
        else
          puts "Got response code: #{res.code}" if @options[:verbose]
          puts 'The site is down!'
          exit 1
        end
      end

      private

      def option_parser
        OptionParser.new do |opts|
          opts.banner = 'Usage: drupal_aws status [options]'

          opts.on('-h', 'Display this help message') do |h|
            @options[:help] = true
          end

          opts.on('-v', 'Enable verbose logging') do |v|
            @options[:verbose] = true
          end
        end
      end

      def help
        puts option_parser.help
        exit 0
      end
    end
  end
end
