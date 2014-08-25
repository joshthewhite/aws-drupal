require 'uuid'
require 'pathname'

require_relative 'utils/zip_file_generator'

module DrupalAws
  module Tasks
    class Create

      def initialize
        @options = {}
        @data_dir = File.expand_path(File.dirname(__FILE__) + '/../../../data')
      end

      def run
        option_parser.parse!
        help if @options[:help]
        create
      end

      private

      def create
        # Force the N. Virgina region.
        AWS.config(region: 'us-east-1')

        # Create AWS objects to work with.
        s3  = AWS::S3.new
        ec2 = AWS::EC2.new

        ##
        # Create S3 bucket.
        ##

        puts 'Checking to see if the bucket already exists.'
        bucket = nil
        s3.buckets.each do |b|
          unless b.tags['drupal-launcher'].nil?
            puts "Found bucket named: #{b.name}"
            bucket = b
            break
          end
        end

        if bucket.nil?
          # Everything uploaded to Amazon S3 must belong to a bucket. These buckets are
          # in the global namespace, and must have a unique name.
          uuid = UUID.new
          bucket_name = "drupal-launcher-#{uuid.generate}"

          puts "No bucket found. Creating new bucket named: #{bucket_name}"

          bucket = s3.buckets.create(bucket_name)
          bucket.tags['drupal-launcher'] = 'true'
        end

        ##
        # Upload config data to the S3 bucket.
        ##

        puts 'Generating archive of Puppet config.'

        archive = 'drupal-puppet-config.zip'
        archive_path = "#{@data_dir}/puppet/#{archive}"
        File.delete(archive_path) if File.exist?(archive_path)
        zf = Utils::ZipFileGenerator.new("#{@data_dir}/puppet/content", archive_path)
        zf.write { |file| puts "Deflating #{file}" }

        # These are all the files needed to complete the installation.
        puts 'Uploading Puppet config files to the S3 bucket'
        config_files = %w{drupal-puppet-config.zip cfn-facter-plugin.rb enable-epel-on-amazon-linux-ami puppet-client.template RDS_MySQL_55.template}
        config_files.each do |file|
          s3_obj = bucket.objects[file]
          s3_obj.write(Pathname.new("#{@data_dir}/puppet/#{file}"), acl: :public_read)
        end

        ##
        # Generate KeyPair to use for EC2 instances.
        #
        # Some care is taken here to not end up locked out of the EC2 boxes. There is, however, probably room for improvement.
        ##

        key_pair_file = File.expand_path('~/.ssh/drupal-launcher')
        key_pair_name = 'drupal-launcher'
        key_pair = ec2.key_pairs.detect { |k| k.name == key_pair_name }

        puts "Checking for private key file: #{key_pair_file}"
        if File.exist?(key_pair_file)
          if key_pair.nil?
            abort "The private key found at #{key_pair_file} does not seem to have a public mate on this account. Aborting."
          else
            # Assume that these public and private keys are a matching set.
            # This could be a dangerous assumption...
            puts 'Key pair match found.'
          end
        elsif !key_pair.nil?
          abort "Found key pair #{key_pair_name} on AWS without matching local private key. This issue can be resolved "\
              'by deleting the key pair in your AWS account if it is no longer needed.'
        else
          puts 'Private key not found. Generating new key pair.'
          key_pair = ec2.key_pairs.create(key_pair_name)
          File.open(key_pair_file, 'wb') do |f|
            f.write(key_pair.private_key)
          end
          File.chmod(0600, key_pair_file)
          puts "Created new private key file at: #{key_pair_file}"
        end

        ##
        # Create Cloud Formation Puppet Master stack from a template.
        ##

        # Grab the Cloud Formation templates used to create the stacks.
        master_template = File.open("#{@data_dir}/puppet-master.template", 'rb').read

        # Parameters for the puppet master template.
        master_params = {
            :KeyName => key_pair_name, # KeyPair generated above.
            :BucketName => bucket.name,# Name of the S3 bucket where config data is found.
        }

        puts 'Creating the Puppet Master stack.'
        backspace_count = 0
        master_stack = create_stack('puppet-master', master_template, master_params) do |event|
          msg = "Last Event: #{event.timestamp}: #{event.resource_type} - #{event.logical_resource_id} - #{event.resource_status}"
          print("\b" * backspace_count, ' ' * backspace_count, "\b" * backspace_count, msg)
          backspace_count = msg.length
        end
        print("\b" * backspace_count, ' ' * backspace_count, "\b" * backspace_count)

        puts "Puppet Master stack finished with status: #{master_stack.status}"
        unless %w(CREATE_COMPLETE UPDATE_COMPLETE).include?(master_stack.status)
          # TODO: Delete the stack? What are the possible outcomes?
          abort 'The Puppet Master stack failed to launch successfully. Aborting.'
        end

        # Collect the template output for use in the client template.
        master_outputs = Hash.new
        master_stack.outputs.each { |o| master_outputs[o.key] = o.value }

        ##
        # Create the Cloud Formation Drupal stack from a template.
        ##

        # Grab the Cloud Formation templates used to create the stacks.
        drupal_template = File.open("#{@data_dir}/puppet-drupal.template", 'rb').read

        # Collect the alert email address from the user.
        if @options[:email].nil?
          alert_email = prompt('Enter alert email: ')
        else
          alert_email = @options[:email]
          puts "Using alert email: #{alert_email}"
        end

        # Parameters for the puppet master template.
        drupal_params = {
            KeyName: key_pair_name, # KeyPair generated above.
            BucketName: bucket.name, # Name of the S3 bucket where config data is found.
            PuppetClientSecurityGroup: master_outputs['PuppetClientSecurityGroup'], # Allows the clients to talk to the master.
            PuppetMasterDNSName: master_outputs['PuppetMasterDNSName'], # The master's address.
            OperatorEmail: alert_email, # Who to notify when things go pear-shaped.
        }

        puts 'Creating the Drupal stack.'
        backspace_count = 0
        client_stack = create_stack('drupal', drupal_template, drupal_params) do |event|
          msg = "Last Event: #{event.timestamp}: #{event.resource_type} - #{event.logical_resource_id} - #{event.resource_status}"
          print("\b" * backspace_count, ' ' * backspace_count, "\b" * backspace_count, msg)
          backspace_count = msg.length
        end
        print("\b" * backspace_count, ' ' * backspace_count, "\b" * backspace_count)

        puts "Drupal client stack finished with status: #{client_stack.status}"
        unless %w(CREATE_COMPLETE UPDATE_COMPLETE).include?(client_stack.status)
          # TODO: Delete the stack? What are the possible outcomes?
          abort 'The Puppet Client stack failed to launch successfully. Aborting.'
        end

        # Collect the template output for use in the client template.
        client_outputs = Hash.new
        client_stack.outputs.each { |o| client_outputs[o.key] = o.value }

        client_outputs.each { |key, value| puts "#{key} is #{value}" }

      end

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

      def prompt(*args)
        print(*args)
        gets
      end

      # Create the stack if it does not already exist.
      # Otherwise, ensure it is up to date.
      def create_stack(name, template, parameters)
        cfm = AWS::CloudFormation.new

        stack = cfm.stacks.detect { |s| s.name == name }

        # Helpful when spinning up and down the stack for testing.
        unless stack.nil?
          wait_statuses = %w{DELETE_IN_PROGRESS ROLLBACK_IN_PROGRESS}
          if stack.status == 'ROLLBACK_COMPLETE'
            stack.delete
            stack = nil
          elsif wait_statuses.include?(stack.status)
            puts 'Stack is being deleted or rolled back. Please wait.'
            sleep 2 while stack.exists? and wait_statuses.include?(stack.status)
            stack = nil
          end
        end

        if stack.nil? or !stack.exists?
          stack = cfm.stacks.create(name, template, parameters: parameters, capabilities: ['CAPABILITY_IAM'])
        else
          # Updating is somewhat problematic because a simple format change will raise an exception.
          stack.update(template: template, parameters: parameters) if template != stack.template
        end

        # Send back the stack progress along the way.
        while stack.status.include? 'PROGRESS'
          last_event = stack.events.first
          yield last_event if block_given?
          sleep 2
        end

        stack
      end
    end
  end
end
