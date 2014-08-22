module DrupalAws
  module Tasks
    class Run
      def run
        target = ARGV.shift || 'help'

        target_object = nil

        case target
          when 'create'
            target_object = Tasks::Create.new
          when 'status'
            target_object = Tasks::Status.new
          when 'help', '-h'
            print_help
            exit 0
          when '-v'
            puts DrupalAws::VERSION
            exit 0
        end

        if target_object.nil?
          puts "Unknown target: '#{target}'."
          print_help
          exit 1
        end

        begin
          target_object.run
        rescue OptionParser::InvalidOption => e
          puts e.message
          exit 1
        end
      end

      def print_help
        puts 'drupal_aws [task] OPTIONS'
        puts 'Append -h for help on specific target.'
        puts ''
        puts 'Available tasks:'
        puts '    create                 Creates a new Drupal stack'
        puts '    status                 Checks on the health of an existing stack'
        puts '    destroy                Tears down an existing stack'
      end
    end
  end
end