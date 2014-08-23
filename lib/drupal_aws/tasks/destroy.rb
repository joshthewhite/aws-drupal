require 'uri'
require 'net/http'

require_relative 'utils/zip_file_generator'

module DrupalAws
  module Tasks
    class Destroy

      def initialize
        @options = {}
        @data_dir = File.expand_path(File.dirname(__FILE__) + '/../../../data')
      end

      def run
        option_parser.parse!
        help if @options[:help]

        exit 0 unless are_you_sure?

        # Force the N. Virgina region.
        AWS.config(region: 'us-east-1')

        # Create AWS objects to work with.
        s3  = AWS::S3.new
        ec2 = AWS::EC2.new
        cfm = AWS::CloudFormation.new

        ##
        # Tear Down S3 bucket.
        ##

        puts 'Checking to see if the bucket exists.'
        bucket = nil
        s3.buckets.each do |b|
          unless b.tags['drupal-launcher'].nil?
            puts "Found bucket named: #{b.name}"
            bucket = b
            break
          end
        end

        if bucket.nil?
          puts 'No bucket found.'
        else
          print 'Deleting the bucket ... '
          bucket.delete!
          print "Done!\n"
        end

        ##
        # Remove the KeyPair used.
        ##

        key_pair_file = File.expand_path('~/.ssh/drupal-launcher')
        key_pair_name = 'drupal-launcher'
        key_pair = ec2.key_pairs[key_pair_name]

        puts "Checking for private key file: #{key_pair_file}"
        if File.exist?(key_pair_file)
          if key_pair.exists?
            # Assume that these public and private keys are a matching set.
            # This could be a dangerous assumption...
            puts 'Key pair match found.'

            print 'Deleting the EC2 key pair ... '
            key_pair.delete
            print "Done!\n"

            print "Deleting private key file #{key_pair_file} ... "
            File.delete(key_pair_file)
            print "Done!\n"
          else
            puts "The private key found at #{key_pair_file} does not seem to have a public mate on this account. Skipping."
          end
        elsif key_pair.exists?
          print 'Deleting the EC2 key pair ... '
          key_pair.delete
          print "Done!\n"
        else
          puts 'No key pairs found. Skipping.'
        end

        # TODO: Add event tracking to the stack deletions.

        ##
        # Delete the Cloud Formation Drupal stack.
        ##
        master_stack = cfm.stacks['puppet-master']
        if master_stack.exists?
          print 'Deleting the Puppet Master stack (this could take a while) ... '
          master_stack.delete
          print "Done!\n"
        end

        ##
        # Delete the Cloud Formation Puppet Master stack.
        ##
        drupal_stack = cfm.stacks['drupal']
        if drupal_stack.exists?
          print 'Deleting the Puppet Master stack (get comfortable, this takes forever) ... '
          drupal_stack.delete
          print "Done!\n"
        end
      end

      private

      def option_parser
        OptionParser.new do |opts|
          opts.banner = 'Usage: drupal_aws destroy [options]'

          opts.on('-h', 'Display this help message') do |h|
            @options[:help] = true
          end

          opts.on('-y', 'Delete the stack without prompt') do |y|
            @options[:yes] = true
          end
        end
      end

      def help
        puts option_parser.help
        exit 0
      end

      def are_you_sure?
        return true if @options[:yes]

        print 'Are you sure you want to destroy your Drupal install? This operation cannot be undone! [y/N]'

        case gets.strip!
        when 'y', 'Y'
          true
        else
          false
        end
      end
    end
  end
end
