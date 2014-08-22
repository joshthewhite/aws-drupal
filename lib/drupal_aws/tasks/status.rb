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
        stack = cfm.stacks.detect { |stack| /drupal-WebServer/.match(stack.name) }

        if stack.nil? or !stack.exists?
          puts 'The stack is down :('
          exit 1
        end

        resource = stack.resources.detect do |resource|
          resource.logical_resource_id == 'PuppetClient'
        end

        if resource.nil?
          puts 'No web server could be found in the stack.'
          exit 1
        end

        web_server = ec2.instances[resource.physical_resource_id]
        host = web_server.dns_name

        uri = URI.parse("http://#{host}/")
        res = Net::HTTP.get_response(uri)
        if res.code == '200' && /<body.*?>/ =~ res.body
          puts 'The site is up.'
          exit 0
        else
          puts 'The site is down!'
          exit 1
        end
      end

      private

      def option_parser
        OptionParser.new do |opts|
          opts.banner = 'Usage: drupal_aws create [options]'

          opts.on('-e', '--email [EMAIL]', 'Notification email address') do |e|
            @options[:email] = e
          end

          opts.on('-h', 'Display this help message') do |h|
            @options[:help] = true
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
